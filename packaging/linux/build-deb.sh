#!/bin/sh
# Builds a .deb for Debian, Ubuntu, Mint, Pop!_OS... from a release binary:
#
#   packaging/linux/build-deb.sh <WooferSoundPad binary> <version> <out.deb>
#
# Installs system-wide: /usr/bin/WooferSoundPad, the app menu entry and the
# icons. Made with plain ar + tar, so it builds on any Linux (no dpkg needed).

set -eu

BIN=$1
VERSION=$2
OUT=$3
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

data="$WORK/data"
install -D -m 755 "$BIN" "$data/usr/bin/WooferSoundPad"
install -D -m 644 "$ROOT/packaging/linux/woofersoundpad.desktop" "$data/usr/share/applications/woofersoundpad.desktop"
for size in 16 24 32 48 64 128 256 512; do
    install -D -m 644 "$ROOT/assets/icon-$size.png" "$data/usr/share/icons/hicolor/${size}x$size/apps/woofersoundpad.png"
done
install -D -m 644 "$ROOT/assets/logo-mark.svg" "$data/usr/share/icons/hicolor/scalable/apps/woofersoundpad.svg"
install -D -m 644 "$ROOT/LICENSE" "$data/usr/share/doc/woofersoundpad/copyright"

control="$WORK/control"
mkdir -p "$control"
size_kb=$(du -sk "$data" | cut -f1)
cat > "$control/control" <<EOF
Package: woofersoundpad
Version: $VERSION
Architecture: amd64
Maintainer: RshaCuDeVidro <68353146+RshaCuDeVidro@users.noreply.github.com>
Installed-Size: $size_kb
Depends: libc6 (>= 2.17), libx11-6, libgl1
Recommends: curl, pulseaudio-utils | pipewire-pulse
Suggests: ffmpeg, yt-dlp
Section: sound
Priority: optional
Homepage: https://github.com/RshaCuDeVidro/WooferSoundPad
Description: soundboard with live effects, mixer and stage mode
 Fire sounds into Discord, games and streams with hotkeys, through a virtual
 microphone. Bend them live with an effect chain, ride the levels on a mixer,
 go full screen on stage and record anything the computer plays.
 .
 One native executable: no Electron, no account, no telemetry.
EOF
(cd "$data" && find . -type f ! -path ./DEBIAN/\* -exec md5sum {} + | sed 's| \./| |') > "$control/md5sums"

printf '2.0\n' > "$WORK/debian-binary"
tar -C "$control" --owner=0 --group=0 --numeric-owner -czf "$WORK/control.tar.gz" ./control ./md5sums
tar -C "$data" --owner=0 --group=0 --numeric-owner -czf "$WORK/data.tar.gz" ./usr
rm -f "$OUT"
# Member order matters (debian-binary first); ar keeps only the base names
ar rc "$OUT" "$WORK/debian-binary" "$WORK/control.tar.gz" "$WORK/data.tar.gz"
echo "$OUT ($size_kb KB installed)"
