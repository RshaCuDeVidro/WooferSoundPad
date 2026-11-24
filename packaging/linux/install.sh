#!/bin/sh
# WooferSoundPad installer for Linux (per user, no root needed).
#
#   ./install.sh               put WooferSoundPad in your app menu (~/.local)
#   ./install.sh --uninstall   remove it again (your sounds and settings stay)
#
# Set PREFIX to install somewhere else, e.g. sudo PREFIX=/usr/local ./install.sh
# The app does the work itself; this is the same as `WooferSoundPad --install`.

set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$HERE/WooferSoundPad"

if [ ! -f "$APP" ]; then
    echo "error: WooferSoundPad not found next to install.sh" >&2
    exit 1
fi
chmod +x "$APP" 2>/dev/null || true

case "${1:-}" in
    --uninstall | -u | uninstall) exec "$APP" --uninstall ;;
    "" | --install | install) exec "$APP" --install ;;
    -h | --help)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "Unknown option: $1 (use --uninstall or --help)" >&2
        exit 2
        ;;
esac
