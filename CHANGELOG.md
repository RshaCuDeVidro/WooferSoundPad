# Changelog

Every release is built and published by GitHub Actions from a `v*` tag. The
section for that version below becomes the release notes.

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
