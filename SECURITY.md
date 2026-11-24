# Security policy

WooferSoundPad runs on your computer, keeps your library in plain folders and
has no account, telemetry or remote backend. The parts that talk to the outside
world are few; they are described in [PRIVACY.md](PRIVACY.md).

## Reporting a vulnerability

**Please do not open a public issue for a security problem.** Use GitHub's
private reporting instead:

**[Report a vulnerability](https://github.com/RshaCuDeVidro/WooferSoundPad/security/advisories/new)**
(Security → Advisories → Report a vulnerability)

Include what you can:

- the version (`WooferSoundPad --version`, or Settings → About) and your OS;
- what an attacker can do, and what they need to start (a web page? a crafted
  audio file? local access?);
- steps to reproduce, a proof of concept, or a capture;
- whether the issue is already public anywhere.

You get an acknowledgement within **7 days** and an honest answer about whether
it will be fixed and roughly when. Please give a fix a reasonable chance before
publishing. Credit goes in the release notes unless you prefer otherwise.

## Supported versions

Only the latest release gets fixes. The app can update itself from GitHub
releases, so staying current is a switch, not a manual download.

## In scope

- The local control server: key handling, query parsing, the overlay and web
  deck pages.
- The updater: the release metadata it trusts, the SHA-256 check, the swap of
  the running binary.
- Memory safety in the audio decoders and the DSP code (`src/c/`).
- Anything that lets a web page, a sound file, a workspace file or a downloaded
  tool read files, play audio or run code it should not.

## Out of scope

- The app is not code-signed, and unsigned downloads can trip SmartScreen or
  antivirus heuristics. That is a known limitation, explained in the FAQ.
- The control server being reachable from your LAN after you turn that option
  on. It still requires the key, and the option is off by default.
- Missing `pactl`, `zenity`, `curl`, `yt-dlp` or `ffmpeg` on `PATH`, or the
  permissions of tools you installed yourself.
- Content downloaded from MyInstants, SoundButtonsWorld, YouTube or any other
  third-party site. WooferSoundPad is a client and hosts nothing.

## How the risky parts are built

- The control server is **off by default**. When on, it binds `127.0.0.1`
  unless you explicitly allow other devices, and every `/api/` call needs the
  per-install key.
- The update check only reads the latest release from the GitHub API. Nothing
  is downloaded until you confirm. The asset is checked against the release's
  `SHA256SUMS.txt` and started with `--version` before it replaces anything.
- The app never runs a downloaded audio file as code. Effects and cuts are
  applied at playback time; `Save cut to file` is the only write into your
  audio, and only when you click it.
- Third-party helpers (`yt-dlp`, FFmpeg, Deno) come from their official GitHub
  releases, only when you install or update them.

## A note on secrets

The HTTP API key is stored in `config.json` next to your settings. It protects
the local server from other web pages on the same machine, not from someone who
can already read your user files. Do not expose the server to the internet.
