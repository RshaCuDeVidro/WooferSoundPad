#ifndef _WIN32
// sockets, pthreads and timeouts under -std=c99 (not _GNU_SOURCE: see build.zig)
#define _DEFAULT_SOURCE
#endif
#include "woof_http.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
#define close_sock closesocket
typedef CRITICAL_SECTION lock_t;
static void lock_init(lock_t *l) { InitializeCriticalSection(l); }
static void lock_take(lock_t *l) { EnterCriticalSection(l); }
static void lock_give(lock_t *l) { LeaveCriticalSection(l); }
#else
#include <pthread.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <signal.h>
typedef int sock_t;
#define BAD_SOCK (-1)
#define close_sock close
typedef pthread_mutex_t lock_t;
static void lock_init(lock_t *l) { pthread_mutex_init(l, NULL); }
static void lock_take(lock_t *l) { pthread_mutex_lock(l); }
static void lock_give(lock_t *l) { pthread_mutex_unlock(l); }
#endif

#define MAX_PAGES 8
#define MAX_CMDS 64
#define CMD_LEN 256

typedef struct {
    char path[64];
    char type[64];
    char *body;
    int len;
} Page;

static lock_t g_lock;
static int g_lock_ready;
static sock_t g_listen = BAD_SOCK;
static volatile int g_running;
static char g_token[64];
static Page g_pages[MAX_PAGES];
static int g_page_count;
static char *g_state;
static int g_state_len;
static char g_cmds[MAX_CMDS][CMD_LEN];
static int g_cmd_head, g_cmd_count;

#ifdef _WIN32
static HANDLE g_thread;
#else
static pthread_t g_thread;
#endif

static void ensure_lock(void) {
    if (!g_lock_ready) {
        lock_init(&g_lock);
        g_lock_ready = 1;
    }
}

void woof_http_set_page(const char *path, const char *content_type, const char *body, int len) {
    ensure_lock();
    lock_take(&g_lock);
    Page *p = NULL;
    for (int i = 0; i < g_page_count; i++) {
        if (strcmp(g_pages[i].path, path) == 0) p = &g_pages[i];
    }
    if (p == NULL && g_page_count < MAX_PAGES) p = &g_pages[g_page_count++];
    if (p != NULL) {
        snprintf(p->path, sizeof(p->path), "%s", path);
        snprintf(p->type, sizeof(p->type), "%s", content_type);
        free(p->body);
        p->body = (char *)malloc((size_t)len);
        p->len = p->body != NULL ? len : 0;
        if (p->body != NULL) memcpy(p->body, body, (size_t)len);
    }
    lock_give(&g_lock);
}

void woof_http_set_state(const char *json, int len) {
    ensure_lock();
    char *copy = (char *)malloc((size_t)len);
    if (copy == NULL) return;
    memcpy(copy, json, (size_t)len);
    lock_take(&g_lock);
    free(g_state);
    g_state = copy;
    g_state_len = len;
    lock_give(&g_lock);
}

int woof_http_poll(char *buf, int cap) {
    ensure_lock();
    int n = 0;
    lock_take(&g_lock);
    if (g_cmd_count > 0) {
        const char *c = g_cmds[g_cmd_head];
        n = (int)strlen(c);
        if (n >= cap) n = cap - 1;
        memcpy(buf, c, (size_t)n);
        buf[n] = 0;
        g_cmd_head = (g_cmd_head + 1) % MAX_CMDS;
        g_cmd_count--;
    }
    lock_give(&g_lock);
    return n;
}

static void push_cmd(const char *verb, const char *arg) {
    lock_take(&g_lock);
    if (g_cmd_count < MAX_CMDS) {
        int slot = (g_cmd_head + g_cmd_count) % MAX_CMDS;
        snprintf(g_cmds[slot], CMD_LEN, "%s %s", verb, arg);
        g_cmd_count++;
    }
    lock_give(&g_lock);
}

// ── Request handling ────────────────────────────────────────────────────────

static int hexval(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

// Decodes %XX and '+' in place
static void url_decode(char *s) {
    char *w = s;
    for (char *r = s; *r; r++) {
        if (*r == '+') {
            *w++ = ' ';
        } else if (*r == '%' && hexval(r[1]) >= 0 && hexval(r[2]) >= 0) {
            *w++ = (char)(hexval(r[1]) * 16 + hexval(r[2]));
            r += 2;
        } else {
            *w++ = *r;
        }
    }
    *w = 0;
}

// Copies the decoded value of query parameter `name` into out
static int query_param(const char *query, const char *name, char *out, size_t cap) {
    size_t nlen = strlen(name);
    const char *p = query;
    while (p != NULL && *p) {
        if (strncmp(p, name, nlen) == 0 && p[nlen] == '=') {
            const char *v = p + nlen + 1;
            const char *end = strchr(v, '&');
            size_t len = end ? (size_t)(end - v) : strlen(v);
            if (len >= cap) len = cap - 1;
            memcpy(out, v, len);
            out[len] = 0;
            url_decode(out);
            return 1;
        }
        p = strchr(p, '&');
        if (p) p++;
    }
    out[0] = 0;
    return 0;
}

static void send_all(sock_t s, const char *data, int len) {
    while (len > 0) {
        int n = (int)send(s, data, len, 0);
        if (n <= 0) return;
        data += n;
        len -= n;
    }
}

static void respond(sock_t s, const char *status, const char *type, const char *body, int len) {
    char head[512];
    int h = snprintf(head, sizeof(head),
                     "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
                     "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
                     status, type, len);
    send_all(s, head, h);
    if (len > 0) send_all(s, body, len);
}

static void respond_json(sock_t s, const char *status, const char *json) {
    respond(s, status, "application/json", json, (int)strlen(json));
}

// Commands any tool can trigger: /api/<verb>?key=...&name=... or &uid=...
static const char *const k_verbs[] = {"play", "queue", "stop", "pause", "fade", "next", "random", "mute_voice", "stage", "workspace", "show"};

static void handle(sock_t s) {
    char req[4096];
    int got = 0;
    while (got < (int)sizeof(req) - 1) {
        int n = (int)recv(s, req + got, (int)sizeof(req) - 1 - got, 0);
        if (n <= 0) break;
        got += n;
        req[got] = 0;
        if (strstr(req, "\r\n\r\n") != NULL) break;
    }
    if (got <= 0) return;
    req[got] = 0;

    char method[8] = {0};
    char target[1024] = {0};
    if (sscanf(req, "%7s %1023s", method, target) != 2) {
        respond_json(s, "400 Bad Request", "{\"ok\":false}");
        return;
    }
    if (strcmp(method, "OPTIONS") == 0) {
        respond(s, "204 No Content", "text/plain", "", 0);
        return;
    }
    if (strcmp(method, "GET") != 0 && strcmp(method, "POST") != 0) {
        respond_json(s, "405 Method Not Allowed", "{\"ok\":false}");
        return;
    }
    char *query = strchr(target, '?');
    if (query) *query++ = 0;
    const char *path = target;

    // Pages need no key: they hold no data and pass the key from their own URL
    if (strncmp(path, "/api/", 5) != 0) {
        const char *want = strcmp(path, "/") == 0 ? "/deck" : path;
        lock_take(&g_lock);
        for (int i = 0; i < g_page_count; i++) {
            if (strcmp(g_pages[i].path, want) == 0) {
                // Copy under the lock, send outside it
                int len = g_pages[i].len;
                char *body = (char *)malloc((size_t)len + 1);
                char type[64];
                snprintf(type, sizeof(type), "%s", g_pages[i].type);
                if (body) memcpy(body, g_pages[i].body, (size_t)len);
                lock_give(&g_lock);
                if (body) respond(s, "200 OK", type, body, len);
                free(body);
                return;
            }
        }
        lock_give(&g_lock);
        respond(s, "404 Not Found", "text/plain", "Not found", 9);
        return;
    }

    char key[96];
    query_param(query, "key", key, sizeof(key));
    if (g_token[0] == 0 || strcmp(key, g_token) != 0) {
        respond_json(s, "403 Forbidden", "{\"ok\":false,\"error\":\"missing or wrong key\"}");
        return;
    }
    const char *verb = path + 5;
    if (strcmp(verb, "state") == 0) {
        lock_take(&g_lock);
        int len = g_state_len;
        char *body = len > 0 ? (char *)malloc((size_t)len) : NULL;
        if (body) memcpy(body, g_state, (size_t)len);
        lock_give(&g_lock);
        if (body) {
            respond(s, "200 OK", "application/json", body, len);
            free(body);
        } else {
            respond_json(s, "200 OK", "{}");
        }
        return;
    }
    for (size_t i = 0; i < sizeof(k_verbs) / sizeof(k_verbs[0]); i++) {
        if (strcmp(verb, k_verbs[i]) != 0) continue;
        char arg[200];
        char uid[32];
        if (query_param(query, "uid", uid, sizeof(uid)) && uid[0]) {
            snprintf(arg, sizeof(arg), "#%s", uid);
        } else {
            query_param(query, "name", arg, sizeof(arg));
        }
        push_cmd(verb, arg);
        respond_json(s, "200 OK", "{\"ok\":true}");
        return;
    }
    respond_json(s, "404 Not Found", "{\"ok\":false,\"error\":\"unknown command\"}");
}

#ifdef _WIN32
static DWORD WINAPI serve(LPVOID arg) {
#else
static void *serve(void *arg) {
#endif
    (void)arg;
    while (g_running) {
        sock_t c = accept(g_listen, NULL, NULL);
        if (c == BAD_SOCK) {
            if (!g_running) break;
            continue;
        }
        // Don't let a client that never sends anything block everyone
#ifdef _WIN32
        DWORD tv = 2000;
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));
#else
        struct timeval tv = {2, 0};
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#endif
        handle(c);
        close_sock(c);
    }
    return 0;
}

int woof_http_start(int port, int lan, const char *token) {
    ensure_lock();
    woof_http_stop();
    snprintf(g_token, sizeof(g_token), "%s", token ? token : "");
#ifdef _WIN32
    static int wsa_ready;
    if (!wsa_ready) {
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return -1;
        wsa_ready = 1;
    }
#else
    signal(SIGPIPE, SIG_IGN); // a client closing early must not kill the app
#endif
    g_listen = socket(AF_INET, SOCK_STREAM, 0);
    if (g_listen == BAD_SOCK) return -1;
    int yes = 1;
    setsockopt(g_listen, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((unsigned short)port);
    addr.sin_addr.s_addr = htonl(lan ? INADDR_ANY : INADDR_LOOPBACK);
    if (bind(g_listen, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(g_listen, 16) != 0) {
        close_sock(g_listen);
        g_listen = BAD_SOCK;
        return -2;
    }
    g_running = 1;
#ifdef _WIN32
    g_thread = CreateThread(NULL, 0, serve, NULL, 0, NULL);
    if (g_thread == NULL) {
#else
    if (pthread_create(&g_thread, NULL, serve, NULL) != 0) {
#endif
        g_running = 0;
        close_sock(g_listen);
        g_listen = BAD_SOCK;
        return -3;
    }
    return 0;
}

void woof_http_stop(void) {
    if (!g_running) return;
    g_running = 0;
    // Closing the socket wakes accept() up
#ifdef _WIN32
    closesocket(g_listen);
    WaitForSingleObject(g_thread, 3000);
    CloseHandle(g_thread);
#else
    shutdown(g_listen, SHUT_RDWR);
    close(g_listen);
    pthread_join(g_thread, NULL);
#endif
    g_listen = BAD_SOCK;
}

int woof_http_running(void) {
    return g_running ? 1 : 0;
}
