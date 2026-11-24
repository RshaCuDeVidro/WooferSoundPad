#!/bin/sh
# WooferSoundPad installer for Linux (per user, no root needed).
#
#   curl -fsSL https://raw.githubusercontent.com/RshaCuDeVidro/WooferSoundPad/main/install.sh | sh
#
# Downloads the latest release, checks its SHA-256 and puts WooferSoundPad in
# your app menu with its icon (~/.local). Next to a WooferSoundPad binary (the
# release tarball) it installs that one instead of downloading.
#
#   sh install.sh                    install or update
#   sh install.sh --uninstall        remove it again (your sounds and settings stay)
#   sh install.sh --version 1.1.0    a specific release
#
# Set PREFIX to install somewhere else, e.g. sudo PREFIX=/usr/local sh install.sh

set -eu

REPO="RshaCuDeVidro/WooferSoundPad"

say() { printf '%s\n' "$*"; }
die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

fetch() { # url dest
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        die "curl or wget is needed to download WooferSoundPad"
    fi
}

latest_version() {
    fetch "https://api.github.com/repos/$REPO/releases/latest" "$1/latest.json" ||
        die "could not reach GitHub"
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' "$1/latest.json" | head -n 1
}

installed_app() {
    if [ -n "${PREFIX:-}" ]; then
        printf '%s' "$PREFIX/bin/WooferSoundPad"
    else
        printf '%s' "$HOME/.local/bin/WooferSoundPad"
    fi
}

main() {
    action=install
    version=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --uninstall | -u | uninstall) action=uninstall ;;
            --install | install) action=install ;;
            --version | -v)
                [ $# -ge 2 ] || die "--version needs a value, e.g. --version 1.1.0"
                version="${2#v}"
                shift
                ;;
            -h | --help)
                sed -n '2,14p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
                return 0
                ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done

    [ "$(uname -s)" = Linux ] || die "this installer is for Linux; on Windows use the setup .exe from https://github.com/$REPO/releases/latest"

    if [ "$action" = uninstall ]; then
        app="$(installed_app)"
        [ -x "$app" ] || die "WooferSoundPad is not installed at $app"
        exec "$app" --uninstall
    fi

    # The release tarball ships the binary next to this script
    # ($0 is just "sh" when piped from curl)
    here=""
    [ -f "$0" ] && here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    if [ -z "$version" ] && [ -n "$here" ] && [ -f "$here/WooferSoundPad" ]; then
        chmod +x "$here/WooferSoundPad" 2>/dev/null || true
        exec "$here/WooferSoundPad" --install
    fi

    case "$(uname -m)" in
        x86_64 | amd64) ;;
        *) die "WooferSoundPad is built for x86_64 only (this is $(uname -m))" ;;
    esac

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT INT TERM

    [ -n "$version" ] || version="$(latest_version "$tmp")"
    [ -n "$version" ] || die "could not find the latest release"
    name="WooferSoundPad-$version-linux-x86_64"
    base="https://github.com/$REPO/releases/download/v$version"

    say "Downloading WooferSoundPad $version..."
    fetch "$base/$name" "$tmp/WooferSoundPad" || die "download failed: $base/$name"

    if command -v sha256sum >/dev/null 2>&1 && fetch "$base/SHA256SUMS.txt" "$tmp/sums" 2>/dev/null; then
        want="$(grep " $name\$" "$tmp/sums" | cut -d ' ' -f 1)"
        got="$(sha256sum "$tmp/WooferSoundPad" | cut -d ' ' -f 1)"
        [ -n "$want" ] && [ "$want" = "$got" ] || die "checksum mismatch: the download is damaged, try again"
    else
        say "(skipping the checksum: sha256sum or SHA256SUMS.txt not available)"
    fi

    chmod +x "$tmp/WooferSoundPad"
    # The app installs itself: binary, menu entry, icons, desktop caches (and
    # it says so when ~/.local/bin is not on the PATH)
    "$tmp/WooferSoundPad" --install
}

# Everything runs from here, so a download cut short by `curl | sh` does nothing
main "$@"
