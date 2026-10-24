#!/bin/sh
# WooferSoundPad installer for Linux (per-user, no root needed).
#
#   ./install.sh               install into ~/.local
#   ./install.sh --uninstall   remove it again (your sounds and settings stay)
#
# Set PREFIX to install somewhere else, e.g. sudo PREFIX=/usr/local ./install.sh

set -eu

APP=WooferSoundPad
ID=woofersoundpad
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
APPS_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/256x256/apps"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

refresh_caches() {
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPS_DIR" 2>/dev/null || true
    # Bumping the theme folder's mtime makes GTK/Qt rescan it
    touch "$PREFIX/share/icons/hicolor" 2>/dev/null || true
}

uninstall() {
    rm -f "$BIN_DIR/$APP" "$APPS_DIR/$ID.desktop" "$ICON_DIR/$ID.png"
    refresh_caches
    echo "$APP was removed."
    echo "Your sounds and settings were kept. Delete them by hand if you want:"
    echo "  ~/Music/$APP  ~/.config/$APP  ~/.local/share/$APP"
}

install_app() {
    for f in "$APP" "$ID.desktop" "$ID.png"; do
        if [ ! -f "$HERE/$f" ]; then
            echo "error: $f not found next to install.sh" >&2
            exit 1
        fi
    done

    mkdir -p "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"
    install -m 755 "$HERE/$APP" "$BIN_DIR/$APP"
    install -m 644 "$HERE/$ID.png" "$ICON_DIR/$ID.png"
    # Absolute Exec path: ~/.local/bin is not on PATH in every desktop session
    sed "s|^Exec=$APP|Exec=\"$BIN_DIR/$APP\"|" "$HERE/$ID.desktop" > "$APPS_DIR/$ID.desktop"
    chmod 644 "$APPS_DIR/$ID.desktop"
    refresh_caches

    echo "$APP installed to $BIN_DIR/$APP"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "note: $BIN_DIR is not on your PATH. Add it to use '$APP --play ...' from shortcuts." ;;
    esac
    for tool in curl pactl; do
        command -v "$tool" >/dev/null 2>&1 || echo "note: '$tool' was not found. Install it for the full experience (see README)."
    done
    if ! command -v zenity >/dev/null 2>&1 && ! command -v kdialog >/dev/null 2>&1; then
        echo "note: install 'zenity' or 'kdialog' for the file pickers (Import, Browse...)."
    fi
    echo "Launch it from your app menu or run: $APP"
}

case "${1:-}" in
    --uninstall | -u | uninstall) uninstall ;;
    "" | --install | install) install_app ;;
    -h | --help)
        sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "Unknown option: $1 (use --uninstall or --help)" >&2
        exit 2
        ;;
esac
