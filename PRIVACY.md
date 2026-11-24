# Privacy

WooferSoundPad has **no account, no analytics, no telemetry and no crash
reporting**. Nothing is sent anywhere unless you use a feature that needs the
network. This page lists every request the app can make, so you can check for
yourself.

## What stays on your computer

- Settings, statistics and play history (`config.json`, `stats.json`).
- Workspaces, audio files and `workspace.json`.
- Measured loudness, waveform cache, thumbnails and temporary downloads.
- The local HTTP key.

They live in your user folders, or in `data/` next to the executable in
[portable mode](README.md#portable-mode-and-where-your-data-lives). Nothing is
uploaded, synced or backed up by the app.

## Network requests

| When | Where | What leaves your computer | Turn it off |
|---|---|---|---|
| On start, then every 12 hours | `api.github.com` | A plain HTTPS request for the latest release. GitHub sees your IP address and the request, like any web request; no account, install ID or library data is sent. | Settings → Updates → automatic update check |
| When you accept an update | `github.com` | Downloads the new binary and `SHA256SUMS.txt`. The checksum is verified before installing. | Do not accept; or turn the check off |
| Explore (MyInstants, SoundButtonsWorld) | `myinstants.com`, `soundbuttonsworld.com` and their media hosts | Your search text, page requests, preview and download requests. | Do not open Explore |
| YouTube & more | The site you paste or search, through `yt-dlp` | The URL or search text, plus the requests `yt-dlp` normally makes. | Do not use the page |
| Downloads & tools | `github.com` (yt-dlp, FFmpeg, Deno) | A download request when you click Install or Update. | Use tools already on your `PATH` |
| Links in the app (VB-Cable, GitHub, docs) | Your default browser | Opens the URL; the app itself sends nothing. | Do not click |

Search results and thumbnails come straight from those sites. Their terms and
privacy policies apply, and they see your IP address as they would in a browser.

## Local control server

The OBS / Stream Deck server is **off by default**. When you turn it on it
listens on `127.0.0.1` (this computer only) and every `/api/` call requires the
key shown in Settings. The *Allow other devices on the network* option is
opt-in; only then does it listen on your LAN. The overlay and web deck pages are
embedded in the executable and load nothing from the internet.

## Updates and signatures

The updater trusts the GitHub release metadata, then verifies the downloaded
file against the release's `SHA256SUMS.txt` and runs it with `--version` before
swapping it in. Releases are built by GitHub Actions from this repository. They
are not code-signed, so SmartScreen and some antivirus engines may warn about a
new binary; see the FAQ.

## Children, ads and tracking

There are no ads, no trackers, no cookies, no fingerprinting and no profiling.
The app does not know or care who you are.

## Questions

Open an issue for anything unclear in this document. For a security problem,
use [SECURITY.md](SECURITY.md) instead of a public issue.

_Last updated: 2026-11-22_
