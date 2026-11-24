# Changelog

Every release is built and published by GitHub Actions from a `v*` tag. The
section for that version below becomes the release notes.

## [1.1.0] - 2026-10-24

### Added

- Updates inside the app: WooferSoundPad looks for a new release when it opens and asks before installing anything. One click downloads it, checks its SHA-256, makes sure it starts on your computer and restarts into the new version. Your sounds and settings stay. Can be turned off in Settings.
- Linux install: one click (or `WooferSoundPad --install`) puts the app in your app menu with its icon in every size, quick actions (random sound, pause, stop all) and the right dock icon. No root needed, and it can be removed from Settings or with `--uninstall`.
- Changelog tab in Settings, in English and Portuguese.
- Master bus: a 3-band EQ, a compressor and a limiter on everything the pads play. The limiter is on by default, so pads playing together never clip.
- Global effect: hold a key and a preset (Radio by default) goes over everything that plays; a switch keeps it on.
- Output per pad: both, only you (headphones) or only the virtual mic, for cues the call never hears.
- Pads that play by themselves, every N minutes or every day at a set time.
- Several pads at once: Ctrl+click (or Ctrl+A), then change their volume, output or effects, star, move or delete them together.
- Undo for deletes: a deleted pad goes to a trash with an Undo button (and Ctrl+Z), instead of a confirmation dialog.
- Slice at silences: one long recording becomes a pad per piece, with the cuts shown on the waveform before anything is written.
- Watched folders: files dropped into a workspace folder become pads right away, and pads whose file was deleted go away.
- Search by speech (optional, offline): whisper.cpp transcribes each sound once, and the search finds a sound by what is said in it. It uses the graphics card when the whisper.cpp build can (Vulkan, CUDA; an NVIDIA build is one click away on Windows), runs at the lowest CPU priority, and lets you pick a fast or a precise model, the language and how much of each sound to listen to.
- A QR code for the web deck in Settings: point your phone's camera at it.
- Windows installer with Start menu and desktop shortcuts and an uninstaller in Settings > Apps, and a `.deb` for Debian, Ubuntu and Mint.

### Fixed

- Opening a dropdown (sort order, the workspace pickers) could crash the app, and choosing a language, sort order or audio device from a dropdown could have no effect.
- Settings, and the changelog tab even more, were slow: drawing and wrapping text did far more work than needed.

### Changed

- The `install.sh` in the Linux tarball now runs the app's own installer, so both install the same way.

## [1.0.1] - 2026-10-24

### Fixed

- The Linux binaries of 1.0.0 were built for the build server's processor and crashed with "Illegal instruction" on many CPUs. They now target any x86_64 processor, and every release runs them on a generic CPU before publishing. Windows was not affected.

## [1.0.0] - 2026-10-24

The first public release.

### Play

- Soundboard of colored pads with waveforms, status LEDs, hotkeys, tags for what changes how a pad plays, search, favorites and four sort orders.
- Restart, overlap or toggle when a playing sound is triggered again; pause and resume everything with Space.
- Play queue: Shift+click, drag to reorder, shuffle, repeat, time left.
- Global hotkeys on Windows and X11, desktop-shortcut commands for Wayland, number keys 1–0.

### Shape

- Live effect chain per pad, up to eight effects in any order: pitch, low-pass, high-pass, radio, distortion, bitcrusher, echo, reverb, chorus, tremolo, robot, gain.
- Automation: any parameter can glide to an end value over the sound.
- Twelve built-in presets (Demonic, Chipmunk, Robot, Radio, Cave, Underwater, Blown out, Ghost, Lo-fi, Echo, Power down, Riser) and your own saved presets.
- Variants: several pads playing one file, each with its own cut, settings and effects.
- Waveform editor with zoom, drag-to-select, click-to-audition, fade handles, exact start and end, auto-trim of silence, loop preview, undo and redo.
- Non-destructive by default; *Save cut to file* writes the cut with ffmpeg when you want it.

### Perform

- Mixer dock: master strip plus one channel strip per playing sound with meter, fader, mute, fade-out and stop.
- Stage mode (F11): full screen, huge pads, ON AIR strip, panic button.
- Virtual microphone: one click on Linux (PipeWire / PulseAudio) with voice volume and mute, VB-Cable on Windows.
- Local control server for OBS and Stream Deck: transparent browser-source overlay, web deck for any browser or phone, and an HTTP API protected by a key.

### Collect

- Explore MyInstants and SoundButtonsWorld inside the app, with previews and one-click add.
- YouTube, SoundCloud and 1000+ sites through yt-dlp, with optional trim and loudness normalization; yt-dlp, ffmpeg and Deno install with one click.
- Recorder: capture what the computer plays (monitor / WASAPI loopback) or a microphone, cut the silence, add it as a pad.

### Keep

- Workspaces are plain folders with a `workspace.json`.
- Library-wide loudness normalization that can be switched on and off; files are never changed.
- Statistics: total plays, time played, plays today and streak, meme ranking, 14-day chart, history.
- 14 themes, English and Brazilian Portuguese, UI scale, portable mode.
