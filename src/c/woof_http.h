#ifndef WOOF_HTTP_H
#define WOOF_HTTP_H

// Tiny local HTTP server for OBS (browser source overlay), Stream Deck and
// other tools that can call a URL. It never touches app state: commands go
// into a queue the UI thread polls, and /api/state serves the last JSON the
// UI thread published. Every /api/ call needs ?key=<token>.

// lan = 0 listens on 127.0.0.1 only. Returns 0 on success.
int woof_http_start(int port, int lan, const char *token);
void woof_http_stop(void);
int woof_http_running(void);

// Static page served at `path` (e.g. "/overlay"). Copied.
void woof_http_set_page(const char *path, const char *content_type, const char *body, int len);
// JSON served at /api/state. Copied.
void woof_http_set_state(const char *json, int len);
// Next queued command as "verb argument" (argument may be empty).
// Returns its length, 0 when the queue is empty.
int woof_http_poll(char *buf, int cap);

#endif
