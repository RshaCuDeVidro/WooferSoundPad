<div align="center">

<img src="assets/banner.png" alt="WooferSoundPad: soundboard, live effects, mixer and stage mode for Linux and Windows" width="100%">

<br>

[![Build](https://img.shields.io/github/actions/workflow/status/RshaCuDeVidro/WooferSoundPad/ci.yml?branch=main&style=flat-square&label=build&labelColor=141414&color=FF6B1A)](https://github.com/RshaCuDeVidro/WooferSoundPad/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RshaCuDeVidro/WooferSoundPad?style=flat-square&label=release&labelColor=141414&color=FF6B1A)](https://github.com/RshaCuDeVidro/WooferSoundPad/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/RshaCuDeVidro/WooferSoundPad/total?style=flat-square&label=downloads&labelColor=141414&color=FFB020)](https://github.com/RshaCuDeVidro/WooferSoundPad/releases)
[![Platforms](https://img.shields.io/badge/platform-linux%20%7C%20windows-EDEAE3?style=flat-square&labelColor=141414)](#download)
[![Zig](https://img.shields.io/badge/zig-0.17-EDEAE3?style=flat-square&labelColor=141414)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-EDEAE3?style=flat-square&labelColor=141414)](LICENSE)

### A soundboard built like an instrument.

Fire sounds into Discord, games and streams with hotkeys. Bend them live with an effect chain,<br>
ride the levels on a mixer, go full screen on stage, record anything your PC plays.<br>
One native executable. No Electron, no account, no API keys.

**[Download](https://github.com/RshaCuDeVidro/WooferSoundPad/releases/latest)** &nbsp;·&nbsp;
**[Tutorial](docs/TUTORIAL.md)** &nbsp;·&nbsp;
**[Português](README.pt-BR.md)** &nbsp;·&nbsp;
**[OBS & Stream Deck](#obs--stream-deck)**

<br>

<img src="docs/screenshots/live.gif" alt="Pads playing with live meters and the mixer moving" width="100%">

</div>

<br>

## What's inside

<table>
<tr>
<td width="33%" valign="top">

**PLAY**

Pads with waveforms, status LEDs and big readable hotkeys. Restart, overlap or toggle mode. A play queue with drag-to-reorder, shuffle and repeat. Global hotkeys while you game. A 0–9 number row.

</td>
<td width="33%" valign="top">

**SHAPE**

Twelve live effects you can chain and reorder: pitch, filters, radio, distortion, bitcrusher, echo, reverb, chorus, tremolo, robot, gain. Automate any parameter over the sound. Save presets. Make variants of one file.

</td>
<td width="33%" valign="top">

**PERFORM**

A mixer with a channel strip per sound: meter, fader, mute, fade-out. Stage mode: full screen, huge pads, a panic button. A web deck for your phone and an overlay for OBS.

</td>
</tr>
<tr>
<td valign="top">

**EDIT**

A zoomable waveform editor: drag to select, click to audition, fade handles on the wave, exact start and end with 10 ms nudges, auto-trim of silence, loop preview, undo and redo. Nothing touches the file until you say so.

</td>
<td valign="top">

**COLLECT**

Browse MyInstants and SoundButtonsWorld inside the app. Search YouTube and SoundCloud or paste any of 1000+ sites (yt-dlp, no keys). Record what your computer is playing. Drag and drop files.

</td>
<td valign="top">

**KEEP**

Workspaces are plain folders. Library-wide loudness normalization you can switch on and off. Statistics: total plays, time played, the meme ranking, a 14-day chart and your history. Portable mode for a USB stick.

</td>
</tr>
</table>

<br>

## Screenshots

<table>
<tr>
<td colspan="2"><img src="docs/screenshots/soundboard.png" alt="Soundboard with the mixer docked at the bottom"><br><sub><b>Soundboard + mixer.</b> Tags on each pad say what changes how it plays: FX, LOOP, CUT, VAR (a variant), queue position.</sub></td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/stage.png" alt="Stage mode"><br><sub><b>Stage mode.</b> Full screen, hotkeys you can read from across the room, ON AIR strip, panic button.</sub></td>
<td width="50%"><img src="docs/screenshots/effects.png" alt="Effect chain with automation"><br><sub><b>Effect chain.</b> The "Power down" preset: pitch and a low-pass both glide to their end value.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/editor.png" alt="Waveform editor"><br><sub><b>Editor.</b> Zoomable waveform, fade handles, exact cut, undo.</sub></td>
<td><img src="docs/screenshots/effect-picker.png" alt="Effect picker"><br><sub><b>Twelve effects</b>, each one at most once per chain.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/recorder.png" alt="Recorder"><br><sub><b>Recorder.</b> Capture the computer's output or a mic, cut the silence, keep what you want.</sub></td>
<td><img src="docs/screenshots/stats.png" alt="Statistics"><br><sub><b>Statistics.</b> Plays, time played, the ranking, the last 14 days, history.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/context-menu.png" alt="Pad menu"><br><sub><b>Pad menu.</b> Edit and trim, effects, variants, hotkey, move between workspaces.</sub></td>
<td><img src="docs/screenshots/queue.png" alt="Play queue"><br><sub><b>Queue.</b> Shift+click pads to line them up.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/explore.png" alt="Explore"><br><sub><b>Explore.</b> MyInstants and SoundButtonsWorld: preview, one-click add.</sub></td>
<td><img src="docs/screenshots/youtube.png" alt="YouTube and more"><br><sub><b>YouTube & more.</b> Search with thumbnails, or paste a link.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/integrations.png" alt="OBS and Stream Deck settings"><br><sub><b>OBS & Stream Deck.</b> One switch, ready-to-copy links.</sub></td>
<td><img src="docs/screenshots/web-deck.png" alt="Web deck"><br><sub><b>Web deck.</b> Your pads in any browser, phone included.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/themes.png" alt="Themes"><br><sub><b>14 themes</b> with live previews.</sub></td>
<td><img src="docs/screenshots/light-theme.png" alt="Light theme"><br><sub><b>Snow</b>, one of the light ones.</sub></td>
</tr>
</table>

<br>

## Contents

- [Download](#download)
- [Quick start](#quick-start)
- [Keyboard and mouse](#keyboard-and-mouse)
- [Effects, automation and presets](#effects-automation-and-presets)
- [The editor](#the-editor)
- [Mixer and stage mode](#mixer-and-stage-mode)
- [Recording your computer's audio](#recording-your-computers-audio)
- [Loudness normalization](#loudness-normalization)
- [Statistics](#statistics)
- [OBS & Stream Deck](#obs--stream-deck)
- [Virtual microphone (Discord, games, calls)](#virtual-microphone-discord-games-calls)
- [Global hotkeys](#global-hotkeys)
- [Command line](#command-line)
- [Portable mode and where your data lives](#portable-mode-and-where-your-data-lives)
- [Building from source](#building-from-source)
- [Project structure](#project-structure)
- [FAQ](#faq)
- [Credits and license](#credits-and-license)

<br>

## Download

Every release on the **[Releases page](https://github.com/RshaCuDeVidro/WooferSoundPad/releases/latest)** comes in a few flavors. They all contain the same app.

| File | What it is |
|---|---|
| `WooferSoundPad-<version>-windows-x86_64.exe` | **Windows.** The app itself: one file, double-click and go. |
| `WooferSoundPad-<version>-windows-x86_64-portable.zip` | **Windows, portable.** Extract anywhere (a USB stick): settings, tools and sounds stay in the folder. |
| `WooferSoundPad-<version>-windows-x86_64-compact.zip` | **Windows, compact.** Just the `.exe`, compressed to under half the size for slow connections. |
| `WooferSoundPad-<version>-linux-x86_64` | **Linux.** The app itself: `chmod +x` it and run. |
| `WooferSoundPad-<version>-linux-x86_64-compact` | **Linux, compact.** The same binary packed with UPX, about a third of the size; it unpacks in memory at start. |
| `WooferSoundPad-<version>-linux-x86_64.tar.gz` | **Linux, with installer.** Adds it to your app menu with its icon: `./install.sh`. |
| `SHA256SUMS.txt` | Checksums: `sha256sum -c SHA256SUMS.txt --ignore-missing` |

<details>
<summary><b>Requirements</b></summary>

<br>

**Linux** (x86_64)

- An X11 or Wayland desktop (Wayland runs it through XWayland) with OpenGL 3.3.
- `curl` for web requests (installed almost everywhere).
- `pactl` for the one-click virtual microphone and for recording the computer's audio (`pipewire-pulse` or `pulseaudio-utils`).
- `zenity` or `kdialog` for the Import and Browse file pickers.

**Windows** 10 (1803 or newer) or 11, x86_64

- Nothing to install. [VB-Cable](https://vb-audio.com/Cable/) (free) if you want to play into voice chat.

</details>

<details>
<summary><b>Linux installer</b></summary>

<br>

```sh
tar -xzf WooferSoundPad-*-linux-x86_64.tar.gz
cd WooferSoundPad
./install.sh              # ~/.local/bin, app menu entry and icon
./install.sh --uninstall  # removes them again; your sounds and settings stay
```

No root needed. `sudo PREFIX=/usr/local ./install.sh` installs system-wide.

</details>

<br>

## Quick start

> The friendly, step-by-step version is the **[tutorial](docs/TUTORIAL.md)**.

1. **Run it.** A 30-second tour opens the first time (F1 brings it back).
2. **Add sounds.** Drag files onto the window, press Ctrl+O, grab them from **Explore**, download from **YouTube & more**, or hit **REC** to record what your PC is playing.
3. **Play.** Click a pad, press 1–9 / 0, or give it a hotkey (right-click → Set hotkey). Space pauses everything, Esc stops everything.
4. **Shape.** Right-click → Effects. Pick a preset like Demonic, Robot or Power down, or build a chain. Right-click → Create variant to keep the clean version too.
5. **Go live.** Settings → Virtual microphone to play into Discord. Open the **mixer** from the toolbar, or press **F11** for stage mode.

<br>

## Keyboard and mouse

| Key | Action |
|---|---|
| <kbd>1</kbd> … <kbd>9</kbd>, <kbd>0</kbd> | Play the first ten pads (Settings can turn this off) |
| <kbd>Space</kbd> | Pause everything / resume it. In the editor: play or stop the preview |
| <kbd>Esc</kbd> | Stop everything (and the queue) |
| <kbd>F11</kbd> | Stage mode on / off |
| <kbd>Pause</kbd> | Global stop-all (change it in Settings → Hotkeys) |
| <kbd>Shift</kbd> + click a pad | Add it to the queue |
| Right-click a pad | Play, pause, queue, edit and trim, effects, create variant, hotkey, favorite, duplicate, show in folder, move, delete |
| Right-click a pad in stage mode | Stop just that sound |
| <kbd>Ctrl</kbd>+<kbd>1</kbd> … <kbd>6</kbd> | Soundboard, Explore, YouTube & more, Downloads, Statistics, Settings |
| <kbd>Ctrl</kbd>+<kbd>F</kbd> / <kbd>Ctrl</kbd>+<kbd>O</kbd> | Search sounds / import files |
| <kbd>Ctrl</kbd>+<kbd>Z</kbd>, <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> or <kbd>Ctrl</kbd>+<kbd>Y</kbd> | Undo / redo in the editor |
| Mouse wheel on the waveform | Zoom (with <kbd>Shift</kbd>: scroll sideways) |
| <kbd>F1</kbd> | The tour |

<br>

## Effects, automation and presets

Every pad has an **effect chain** of up to eight effects, applied live, in order, while it plays. Change a value and you hear it right away, even on a sound that is already playing. The file on disk never changes.

| Effect | Parameters | Good for |
|---|---|---|
| Pitch | semitones (−12 … +12) | Higher or lower without changing the speed |
| Low-pass | cutoff, resonance | Muffled, behind a wall, underwater |
| High-pass | cutoff, resonance | Thin, no bass |
| Radio / phone | center, width | Old radio, phone call |
| Distortion | drive, mix | Crunchy, blown out |
| Bitcrusher | bits, sample hold, mix | 8-bit, retro games |
| Echo | time, feedback, mix | Repeats that fade away |
| Reverb | room size, damping, mix | Room, hall, cave |
| Chorus | rate, depth, mix | Wide, wobbly, dreamy |
| Tremolo | rate, depth | Pulsing volume |
| Robot | ring frequency, mix | Metallic voices |
| Gain | dB (−24 … +24) | Louder or quieter |

**Automation.** Click the small line-chart button next to any parameter and it gets a second value, *At the end*. The parameter glides from the first to the second over the length of the sound (and starts again when it loops). Pitch from 0 to −12 with a closing low-pass is the classic "power down"; the reverse is a riser.

**Presets.** Twelve come built in: Demonic, Chipmunk, Robot, Radio, Cave, Underwater, Blown out, Ghost, Lo-fi, Echo, Power down and Riser. Build a chain you like, name it and **Save**: your presets show up next to the built-in ones on every pad.

**Variants.** A variant is a second pad that plays the **same file** with its own name, cut, settings and effects: "BRUH" and "BRUH (Demonic)" without a second copy of the audio. Right-click → **Create variant**, or the button in the editor. Variants are tagged **VAR**; deleting or moving one never breaks the others.

**Compare.** The *Compare* switch bypasses the chain while you listen, so you can A/B the effect against the dry sound.

<br>

## The editor

Right-click a pad → **Edit & trim** (or Effects).

- **Waveform.** Drag across it to select what plays; drag the white handles to adjust; click anywhere to play from there. The round handles at the top set the fade-in and fade-out right on the wave.
- **Zoom.** Mouse wheel, the buttons, *zoom to the cut*, or drag the strip under the ruler to scroll.
- **Exact cut.** Type start and end, nudge them by 10 ms (100 ms with Shift), or snap them to where the sound is playing.
- **Auto-trim** cuts silence at the start and end. **Loop preview** keeps the cut playing while you work.
- **Sound tab:** volume, speed (0.5× to 2×, changes pitch too), fades, loop. **Effects tab:** the chain. **Pad tab:** color, hotkey, and what the app knows about the sound (plays, time played, measured loudness).
- **Undo / redo** every step: Ctrl+Z, Ctrl+Shift+Z, or the arrows in the header.
- **Save cut to file** writes the cut into the audio for good (needs ffmpeg). If other variants use the file, this pad gets a file of its own and they keep the original.

<br>

## Mixer and stage mode

**The mixer** docks under the soundboard (toolbar button, or the stage mode toolbar). The master strip has the master fader, *FADE* (fades everything out) and *STOP*, plus the fade length. Then every sound that is playing gets a channel strip:

| Control | What it does |
|---|---|
| Meter | Output level after effects, LED-style |
| Fader | Volume of this play only, 0–200%, with a mark at 100% |
| M | Mute this sound |
| F | Fade it out over the fade length |
| ■ | Stop it now |

Live mixer changes reset on the next play; the pad's own volume is in the editor.

**Stage mode** (F11, or **STAGE** in the header) is the soundboard for when you are live: full screen, huge pads with their hotkeys, an *ON AIR* strip with what is playing (click one to stop it), the mixer at the bottom and a big **STOP EVERYTHING** button. Esc still stops everything, number keys still play. Settings → Appearance decides whether it goes full screen.

<br>

## Recording your computer's audio

Click **REC** in the soundboard header.

1. Choose a **source**: *Computer audio (what you hear)*, the default microphone, or any input device.
2. Hit the red button, play whatever you want to catch, hit it again. You see the waveform and the level while it records (up to 10 minutes).
3. Drag the handles to keep the part you want. *Cut silence automatically* does a first pass for you.
4. Name it, pick a workspace, **Add to soundboard**. It is saved as a WAV and opens in the editor.

Computer audio is captured from the monitor of your default output on Linux (PipeWire / PulseAudio) and with WASAPI loopback on Windows.

<br>

## Loudness normalization

Sounds from the internet come at every volume. Settings → Audio → **Even out the library's volume** measures each file once (gated loudness, like broadcast meters) and plays every pad at the **target loudness** you choose. It never boosts a sound past −1 dBFS, so loud peaks do not clip. Files are not changed, measurements are saved with the workspace, and switching it off puts every sound back to how it was. The editor's Pad tab shows each sound's measured loudness and the gain applied.

<br>

## Statistics

The Statistics page (Ctrl+5) counts every play: total plays, time played, plays today and your streak, how many of your sounds you actually use, the meme ranking, a 14-day chart and the history of what played when. Look at all workspaces or just the current one. *Clear history* wipes the history and the chart; per-sound totals stay.

<br>

## OBS & Stream Deck

Settings → **OBS & Stream Deck** → turn on the **local control server**. It listens on `127.0.0.1:8737` (only this computer) unless you allow other devices on the network. The page shows ready-to-copy links with your key.

**OBS overlay.** Add a *Browser Source* with the overlay link. It is transparent and shows each sound as it plays, with a progress bar. URL options: `&align=right`, `&scale=1.5`, `&label=0` (hides the ON AIR tag).

**Web deck.** Open the deck link in any browser: your pads, workspace switching, FADE and STOP. With the network option on, swap `127.0.0.1` for your PC's IP and use it from your phone.

**Stream Deck, Touch Portal, macros, scripts.** Anything that can open a URL can drive the app. Use a "Website" action set to open in the background, or any web-request plugin:

```text
http://127.0.0.1:8737/api/play?key=YOUR_KEY&name=bruh        play by name (exact, then partial match)
http://127.0.0.1:8737/api/play?key=YOUR_KEY&uid=12           play by id (from /api/state)
http://127.0.0.1:8737/api/queue?key=YOUR_KEY&name=vine boom  add to the queue
http://127.0.0.1:8737/api/stop?key=YOUR_KEY                  stop everything
http://127.0.0.1:8737/api/fade?key=YOUR_KEY                  fade everything out
http://127.0.0.1:8737/api/pause?key=YOUR_KEY                 pause / resume
http://127.0.0.1:8737/api/next?key=YOUR_KEY                  next in the queue
http://127.0.0.1:8737/api/random?key=YOUR_KEY                a random sound
http://127.0.0.1:8737/api/stage?key=YOUR_KEY                 stage mode on / off
http://127.0.0.1:8737/api/workspace?key=YOUR_KEY&name=Gaming switch workspace
http://127.0.0.1:8737/api/mute_voice?key=YOUR_KEY            mute / unmute your voice (Linux)
http://127.0.0.1:8737/api/state?key=YOUR_KEY                 JSON: workspace, sounds, what is playing
```

Every `/api/` call needs the key, so a random web page open in your browser cannot trigger sounds. **New key** in Settings invalidates old links.

<br>

## Virtual microphone (Discord, games, calls)

Every sound plays on **two outputs at once**: your headphones and a *virtual mic output* that feeds voice chat, each with its own volume (Settings → Audio). The sidebar fader is the master for the sounds; it never touches your real microphone.

<details open>
<summary><b>Linux (PipeWire or PulseAudio): one click</b></summary>

<br>

1. Settings → **Virtual microphone**.
2. Leave **Mix my real microphone in** on if your friends should keep hearing you.
3. Click **Create virtual mic**. *Virtual mic output* is set to **WooferSoundPad** automatically.
4. In Discord → Voice & Video → Input Device, choose **WooferSoundPad Mic**. Same in games, OBS, call apps.

This loads three `pactl` modules: a null sink (`woofer_sink`), a loopback of your mic into it and a remapped source (`woofer_mic`). **Remove** unloads them; after a reboot just create it again. With your mic mixed in you also get **My voice volume** (0–150%), **Mute my voice**, a mic button in the sidebar and a mute hotkey.

Discord's noise suppression can eat sound effects; turn it down if sounds come through choppy.

</details>

<details>
<summary><b>Windows (VB-Cable)</b></summary>

<br>

1. Install **[VB-Cable](https://vb-audio.com/Cable/)** as administrator and reboot (Settings → Virtual microphone has a link).
2. Settings → Virtual microphone shows **VB-Cable detected**: click **Use it**.
3. In Discord, choose **CABLE Output (VB-Audio Virtual Cable)** as the input device.
4. To keep your voice: Windows sound settings → Recording → your mic → Properties → Listen → **Listen to this device** through **CABLE Input**.

Never make *CABLE Input* your default playback device, or every app's audio goes to your friends.

</details>

<br>

## Global hotkeys

Give any sound a hotkey (right-click → Set hotkey) such as `F5`, `Ctrl+Shift+F1` or `Alt+Num3`. Conflicts are flagged. Hotkeys belong to the **active workspace**, so one key can play different sounds in *Gaming* and *Stream*. Settings → Hotkeys adds app-wide keys: stop all (default `Pause`), pause / resume, next in queue, random sound and mute my voice.

| Platform | How |
|---|---|
| Windows | System-wide through `RegisterHotKey`, works inside games |
| Linux on X11 | System-wide through `XGrabKey` |
| Linux on Wayland | Apps cannot grab keys globally. Bind desktop shortcuts to the [command line](#command-line) (or to the [HTTP API](#obs--stream-deck)) |

<details>
<summary><b>Desktop shortcuts on Wayland: KDE, GNOME, Hyprland, Sway</b></summary>

<br>

**KDE Plasma:** System Settings → Keyboard → Shortcuts → Add New → Command or Script: `WooferSoundPad --play "bruh"`.

**GNOME:** Settings → Keyboard → Custom Shortcuts → **+**, command `WooferSoundPad --play "bruh"`.

**Hyprland** (`~/.config/hypr/hyprland.conf`):

```ini
bind = SUPER, F1, exec, WooferSoundPad --play "bruh"
bind = SUPER, Escape, exec, WooferSoundPad --stop
bind = SUPER, Space, exec, WooferSoundPad --pause
bind = SUPER, R, exec, WooferSoundPad --random
```

**Sway** (`~/.config/sway/config`):

```ini
bindsym $mod+F1 exec WooferSoundPad --play "bruh"
bindsym $mod+Escape exec WooferSoundPad --stop
```

Make sure `WooferSoundPad` is on your `PATH` (`install.sh` puts it in `~/.local/bin`). Settings → Hotkeys has a **Copy** button with a ready-made command.

</details>

<br>

## Command line

```text
WooferSoundPad                       start the app
WooferSoundPad --play "<name>"       play a sound in the running app
WooferSoundPad --queue "<name>"      add a sound to the play queue
WooferSoundPad --stop                stop every sound
WooferSoundPad --pause               pause / resume everything
WooferSoundPad --next                skip to the next sound in the queue
WooferSoundPad --random              play a random sound
WooferSoundPad --mute-voice          mute / unmute your voice on the virtual mic
WooferSoundPad --workspace "<name>"  switch workspace
WooferSoundPad --show                bring the window to the front
WooferSoundPad --version             print the version
```

Remote commands reach the running app through a FIFO in `$XDG_RUNTIME_DIR` (Linux). On any platform the [HTTP API](#obs--stream-deck) does the same. On Linux, launching the app a second time just brings the first window forward.

<br>

## Portable mode and where your data lives

Put an empty **`portable.txt`** next to the executable (the portable Windows zip already has it) and everything stays in a `data` folder beside it:

```text
WooferSoundPad/
├── WooferSoundPad(.exe)
├── portable.txt
└── data/
    ├── config.json      settings
    ├── stats.json       play history and daily totals
    ├── tools/           yt-dlp, ffmpeg, deno
    ├── cache/           previews, thumbnails, temporary downloads
    └── Library/         your workspaces
```

Otherwise:

| What | Linux | Windows |
|---|---|---|
| Settings (`config.json`, `stats.json`) | `~/.config/WooferSoundPad/` | `%APPDATA%\WooferSoundPad\` |
| Tools and cache | `~/.local/share/WooferSoundPad/` | `%LOCALAPPDATA%\WooferSoundPad\` |
| Sound library | `~/Music/WooferSoundPad/` | `%USERPROFILE%\Music\WooferSoundPad\` |

**Each workspace is a folder** with its audio files and a `workspace.json` (names, colors, volumes, hotkeys, cuts, effect chains, variants, play counts, measured loudness). Files you copy in by hand show up on the next start. Formats: MP3, WAV, OGG, FLAC.

<br>

## Building from source

You need **[Zig 0.17.0](https://ziglang.org/download/)**. On Linux also the X11 and OpenGL headers:

| Distro | Command |
|---|---|
| Arch / Manjaro | `sudo pacman -S zig libx11 libxrandr libxinerama libxcursor libxi mesa` |
| Debian / Ubuntu | `sudo apt install libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libgl1-mesa-dev` |
| Fedora | `sudo dnf install libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel mesa-libGL-devel` |

Everything else (raylib, GLFW, miniaudio, tinyfiledialogs) is vendored and compiled from source.

```sh
git clone https://github.com/RshaCuDeVidro/WooferSoundPad.git
cd WooferSoundPad
zig build run                                              # debug build, run it
zig build test                                             # unit tests
zig build -Doptimize=ReleaseSmall                          # zig-out/bin/WooferSoundPad
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows  # zig-out/bin/WooferSoundPad.exe, from Linux
```

`-Dversion=<string>` sets the version shown in the app. Pushing a `v*` tag runs the [release workflow](.github/workflows/release.yml): it tests, builds both platforms, packs the compact and portable variants, writes the release notes from [CHANGELOG.md](CHANGELOG.md) and publishes the release.

`WOOFER_AUTOSHOT=1 WooferSoundPad` walks through every screen, saves screenshots and quits (run it under `xvfb-run` to keep it off your desktop).

<br>

## Project structure

<details>
<summary><b>Source files</b></summary>

<br>

| File | Role |
|---|---|
| `src/main.zig` | Entry point: CLI, window, UI scale, main loop |
| `src/app.zig` | App state and logic: workspaces, playback, queue, variants, mixer, stage, recorder, remote commands |
| `src/view.zig` | Frame layout: sidebar, transport, overlays, shared page pieces |
| `src/view_soundboard.zig` | Pads, toolbar, queue panel, pad menu |
| `src/view_mixer.zig` | The mixer dock: master strip and channel strips |
| `src/view_stage.zig` | Stage mode |
| `src/view_editor.zig` | Waveform editor, effect chain, presets, undo |
| `src/view_dialogs.zig` | Dialogs: recorder, download, workspaces, confirmations |
| `src/view_stats.zig` | Statistics page |
| `src/view_explore.zig`, `src/view_online.zig`, `src/view_downloads.zig` | Explore, YouTube & more, Downloads |
| `src/view_settings.zig`, `src/view_onboarding.zig` | Settings, first-run tour |
| `src/ui.zig` | Immediate-mode UI toolkit on raylib: SDF shapes, fonts, widgets, meters, faders |
| `src/theme.zig`, `src/i18n.zig`, `src/icons.zig` | Themes and pad colors, English and Portuguese strings, Lucide codepoints |
| `src/audio.zig`, `src/c/woof_audio.c` | Audio engine on miniaudio: two outputs, per-voice effect nodes, automation, mixer controls, recorder, loudness |
| `src/c/woof_dsp.h` | The effects: pitch shifter, biquads, distortion, bitcrusher, echo, Freeverb, chorus, tremolo, ring mod, gain |
| `src/c/woof_http.c`, `src/remote.zig` | Local HTTP server for OBS / Stream Deck and the app side of it |
| `src/fx.zig` | Effect kinds, parameters, chains, presets |
| `src/loudness.zig` | Background loudness measurement for normalization |
| `src/stats.zig` | Play history and daily totals |
| `src/library.zig` | Workspaces as folders + `workspace.json` |
| `src/waves.zig` | Waveform peaks, decoded in the background |
| `src/market.zig`, `src/tools.zig`, `src/jobs.zig`, `src/net.zig` | Explore clients, yt-dlp / ffmpeg / Deno, background jobs, HTTP via curl |
| `src/hotkeys.zig`, `src/ipc.zig`, `src/vmic.zig` | Global hotkeys, CLI remote control, virtual microphone |
| `src/sys.zig`, `src/config.zig`, `src/devtools.zig` | Platform layer, settings, screenshot automation |
| `assets/` | Logo, icons, fonts, the web deck and overlay pages (all embedded into the executable) |
| `vendor/` | raylib (with GLFW, miniaudio, stb) and tinyfiledialogs |

</details>

Built with [Zig](https://ziglang.org), [raylib](https://www.raylib.com) and [miniaudio](https://miniaud.io). yt-dlp, FFmpeg and Deno are optional and downloaded on demand.

<br>

## FAQ

<details>
<summary><b>I don't hear anything.</b></summary>

<br>

Settings → Audio → Output: try *System default*, or **Refresh devices** if you plugged a headset in after starting. Check the master fader at the bottom of the sidebar and the sound's own volume (Edit → Sound tab).

</details>

<details>
<summary><b>My friends can't hear the sounds.</b></summary>

<br>

*Virtual mic output* must not be Off: it should be WooferSoundPad (Linux) or CABLE Input (Windows), and the sidebar shows *Virtual mic on*. Discord's input must be WooferSoundPad Mic or CABLE Output. Turn Discord's noise suppression down. On Linux, create the virtual mic again after a reboot.

</details>

<details>
<summary><b>Do effects, cuts or normalization change my files?</b></summary>

<br>

No. Effects, cuts, speed, fades, loop and normalization are all applied while the sound plays. Only **Save cut to file** writes into the audio, and only when you click it.

</details>

<details>
<summary><b>Recording "Computer audio" says it isn't supported.</b></summary>

<br>

On Linux it needs PipeWire (with `pipewire-pulse`) or PulseAudio. With plain ALSA there is no monitor to record from; pick a microphone or a loopback device instead.

</details>

<details>
<summary><b>YouTube search or downloads fail.</b></summary>

<br>

Settings → Downloads & tools: **Update** yt-dlp, install **Deno** (yt-dlp needs it for YouTube) and **ffmpeg** for conversion and trimming.

</details>

<details>
<summary><b>Hotkeys don't fire.</b></summary>

<br>

Check *Global hotkeys* in Settings → Hotkeys and whether some keys are taken by other apps. On Wayland use desktop shortcuts or the HTTP API. Hotkeys follow the active workspace.

</details>

<details>
<summary><b>The OBS overlay or Stream Deck link does nothing.</b></summary>

<br>

The server must be on (Settings → OBS & Stream Deck shows *Running on port 8737*). If another app uses the port, pick another one and press Enter. A *wrong or missing key* answer means the link is from before you clicked **New key**: copy it again.

</details>

<details>
<summary><b>My antivirus flags the .exe.</b></summary>

<br>

The executables are not code-signed, and small unsigned programs that download tools sometimes trip heuristic scanners. Every release is built by GitHub Actions from this repository; compare against `SHA256SUMS.txt`, or build it yourself. On SmartScreen: More info → Run anyway.

</details>

<details>
<summary><b>Can I use sounds from MyInstants, SoundButtonsWorld or YouTube?</b></summary>

<br>

WooferSoundPad is a client and hosts nothing. That content belongs to its owners and the sites' terms apply. Respect copyright and keep downloads for personal use.

</details>

<br>

## Credits and license

| Project | Used for | License |
|---|---|---|
| [raylib](https://www.raylib.com) + [GLFW](https://www.glfw.org) | Window, input, OpenGL | zlib |
| [miniaudio](https://miniaud.io) | Audio, devices, decoding, node graph | Public Domain / MIT-0 |
| [stb](https://github.com/nothings/stb) | OGG decoding, images, font rasterization | MIT / Public Domain |
| [tinyfiledialogs](https://sourceforge.net/projects/tinyfiledialogs/) | Native file pickers | zlib |
| [Inter](https://rsms.me/inter/), [JetBrains Mono](https://www.jetbrains.com/lp/mono/), [Outfit](https://github.com/Outfitio/Outfit-Fonts) | Fonts | SIL OFL 1.1 |
| [Lucide](https://lucide.dev) | Icons | ISC |
| [Freeverb](https://ccrma.stanford.edu/~jos/pasp/Freeverb.html) (Jezar at Dreampoint) | The reverb design | Public Domain |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org), [Deno](https://deno.com) | Media download and conversion, downloaded on demand | Unlicense, GPL, MIT |

Sound sources: [MyInstants](https://www.myinstants.com) and [SoundButtonsWorld](https://soundbuttonsworld.com). Full notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md).

WooferSoundPad is released under the **[MIT License](LICENSE)**, © 2026 RshaCuDeVidro.

<br>

<div align="center">
<img src="assets/logo-mark-128.png" width="56" alt="WooferSoundPad">
<br>
<sub>WOOFER<b>SOUNDPAD</b> · <a href="README.pt-BR.md">Português</a> · <a href="docs/TUTORIAL.md">Tutorial</a> · <a href="https://github.com/RshaCuDeVidro/WooferSoundPad/releases">Releases</a></sub>
</div>
