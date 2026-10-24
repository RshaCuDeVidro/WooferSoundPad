# Contributing to WooferSoundPad

Thanks for wanting to help. Bug reports, translations, themes, effects and pull
requests are all welcome.

## Building

You need **Zig 0.17.0** (the standard library changes between versions, so other
versions will not compile the code) and, on Linux, the X11/OpenGL headers:

| Distro | Packages |
|---|---|
| Arch / Manjaro | `sudo pacman -S libx11 libxrandr libxinerama libxcursor libxi mesa` |
| Debian / Ubuntu | `sudo apt install libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libgl1-mesa-dev` |
| Fedora | `sudo dnf install libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel mesa-libGL-devel` |

```sh
zig build run                                              # debug build + run
zig build test                                             # unit tests (parsers, config, i18n...)
zig build -Doptimize=ReleaseSmall                          # release build → zig-out/bin/
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows  # Windows .exe from Linux
```

Everything else (raylib, miniaudio, tinyfiledialogs) is vendored in `vendor/`
and compiled from source, so no other dependency is needed.

## Guidelines

- **Match the surrounding code.** Same naming, same comment style, same
  structure. Run `zig fmt src/` before committing.
- Keep it small and fast: no new dependencies unless there's a really good reason.
- Every user-facing string lives in `src/i18n.zig`. Add it to **both** `en` and
  `pt` (the compiler will complain if you forget one).
- Things that don't need a window or an audio device (parsers, formatting,
  config) should get a `test` block; `src/tests.zig` lists the files that are tested.
- Test on Linux **and** Windows when you touch `sys.zig`, `hotkeys.zig`,
  `vmic.zig`, `ipc.zig` or anything platform-specific. Cross-compiling the
  `.exe` and running it under Wine is a decent first check.
- One topic per pull request, with a short description of *what* and *why*.
  Screenshots/GIFs are great for UI changes.

## Adding a translation

1. Add the language to `Language` in `src/config.zig`.
2. Add a new `Strings` value in `src/i18n.zig` (copy `en` and translate) and
   return it from `get()`.
3. Add its name to the language dropdown in `src/view_settings.zig`.

## Adding an effect

The DSP lives in `src/c/woof_dsp.h` (plain C, runs on the audio thread: no
allocations there; buffers are allocated in `dsp_prepare`). Add a `WOOF_FX_*`
constant in `src/c/woof_audio.h`, the processing function and its `switch`
case in `dsp_process`, then describe it in `src/fx.zig` (kind, icon,
parameters with ranges and defaults) and give it a name and description in
both languages in `src/i18n.zig` (`fx_names`, `fx_descs`).

## Adding a theme

Themes live in `src/theme.zig`: copy an existing `make(...)` entry and tweak
the colors. Check both the soundboard and the dialogs for contrast.

## Checking the UI without clicking around

`WOOFER_AUTOSHOT=1 zig-out/bin/WooferSoundPad` walks through every page (tour, soundboard,
menus, editor, Explore, YouTube, downloads, settings, a light theme) and saves `shot-*.png`
screenshots into the current directory, then quits. Set `WOOFER_AUTOSHOT_WS=<workspace>` to
pick which workspace is shown. To keep it off your desktop and away from your real data:

```sh
HOME=/tmp/woof XDG_RUNTIME_DIR=/tmp/woof/run WOOFER_AUTOSHOT=1 \
  xvfb-run -a -s "-screen 0 1280x800x24" env -u WAYLAND_DISPLAY zig-out/bin/WooferSoundPad
```

The script lives in `src/devtools.zig`. `WOOFER_GIF=1` also saves every frame of
the mixer scene as `gif-*.png` (that is how `docs/screenshots/live.gif` is made).

## Releasing

1. Add a section for the new version at the top of `CHANGELOG.md`
   (`## [1.2.0] - 2026-11-01`).
2. Tag and push: `git tag v1.2.0 && git push origin v1.2.0`.

The [release workflow](.github/workflows/release.yml) runs the tests, builds
Linux and Windows, packs the portable and compact variants, writes the release
notes from that CHANGELOG section and publishes the release. Tags with a dash
(`v1.2.0-beta.1`) become pre-releases. Running the workflow by hand without a
version makes a test build you can download from the run, without publishing.

The Windows build is not UPX-packed on purpose: packed Zig executables crash on
start under Wine, and probably on some Windows setups too.
