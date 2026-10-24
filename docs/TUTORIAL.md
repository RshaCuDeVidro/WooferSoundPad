<div align="center">

<img src="../assets/logo-mark-128.png" width="88" alt="WooferSoundPad">

# The WooferSoundPad tutorial

From zero to firing sounds into your Discord call, with effects, in about ten minutes.

[Português](TUTORIAL.pt-BR.md) &nbsp;·&nbsp; [Back to the README](../README.md)

</div>

<br>

## Contents

1. [First launch](#1-first-launch)
2. [A look around](#2-a-look-around)
3. [Workspaces](#3-workspaces)
4. [Getting sounds in](#4-getting-sounds-in)
5. [Playing sounds](#5-playing-sounds)
6. [The queue](#6-the-queue)
7. [Editing a sound](#7-editing-a-sound)
8. [Effects, presets and automation](#8-effects-presets-and-automation)
9. [Variants: one file, many pads](#9-variants-one-file-many-pads)
10. [The mixer](#10-the-mixer)
11. [Stage mode](#11-stage-mode)
12. [Recording your computer's audio](#12-recording-your-computers-audio)
13. [Playing into Discord (virtual microphone)](#13-playing-into-discord-virtual-microphone)
14. [Hotkeys](#14-hotkeys)
15. [OBS, Stream Deck and your phone](#15-obs-stream-deck-and-your-phone)
16. [Even volumes and statistics](#16-even-volumes-and-statistics)
17. [Settings, themes and portable mode](#17-settings-themes-and-portable-mode)
18. [Handy tips](#18-handy-tips)

<br>

## 1. First launch

1. Get your file from the [Releases page](https://github.com/RshaCuDeVidro/WooferSoundPad/releases/latest):
   - **Windows:** `WooferSoundPad-<version>-windows-x86_64.exe`. Double-click it. If SmartScreen complains, choose *More info → Run anyway* (the app is not code-signed). Prefer everything in one folder? Take the `-portable.zip` instead.
   - **Linux:** `WooferSoundPad-<version>-linux-x86_64.tar.gz`, extract it and run `./install.sh` to get it in your app menu. Or grab the bare `-linux-x86_64` binary, `chmod +x` it and run it.
2. A five-step tour opens. Click through or *Skip*; **F1** brings it back.
3. The app speaks English and Brazilian Portuguese and picks your system language. Change it in *Settings → Appearance*.

You start with one workspace, **My Sounds**, in `~/Music/WooferSoundPad` (Linux) or `C:\Users\<you>\Music\WooferSoundPad` (Windows).

<br>

## 2. A look around

<p align="center"><img src="screenshots/soundboard.png" alt="The soundboard" width="92%"></p>

- **Sidebar, top:** the pages. *Soundboard*, *Explore*, *YouTube & more*, *Downloads*, *Statistics*, *Settings*: **Ctrl+1** to **Ctrl+6**.
- **Sidebar, middle:** your workspaces, with how many sounds each one has.
- **Sidebar, bottom:** the transport. A status LED and what is playing, a master level meter, the **master fader** (volume of the sounds on headphones and virtual mic; it never touches your real mic), *Pause* and *Stop*, and the virtual mic status.
- **Header:** the workspace name (hover it for the rename pencil), how many pads and hotkeys it has, and two buttons: **REC** (recorder) and **STAGE** (stage mode).
- **Toolbar:** search on the left; on the right a group of four toggles (favorites only, random sound, queue panel, mixer), the sort order and **Import**.
- **Pads:** each one shows its number or hotkey, a status LED, the waveform, the name and the time. Small tags tell you what changes how it plays: **FX2** (two effects on), **LOOP**, **CUT**, **1.25x** (speed), **VAR** (a variant), **Q3** (third in the queue).

<br>

## 3. Workspaces

Workspaces are collections: *Memes*, *Gaming*, *Stream*, *Friday night*.

| To | Do this |
|---|---|
| Create one | **+** next to *WORKSPACES*, type a name, *Create* |
| Switch | Click it |
| Rename | Double-click it, right-click → *Rename*, or the pencil next to its name in the header |
| Open its folder | Right-click → *Open folder* |
| Delete | Right-click → *Delete* (deletes its sounds too, after asking) |
| Move a sound | Right-click the pad → under *MOVE TO*, pick the workspace |

Each workspace is a plain **folder** with your audio files and a `workspace.json` (names, colors, volumes, hotkeys, cuts, effects, play counts). Back it up, sync it or share it by copying the folder.

<br>

## 4. Getting sounds in

- **Drag and drop** files onto the window. They go into the workspace you are looking at.
- **Import** (or **Ctrl+O**) and pick files.
- **Explore** (**Ctrl+2**): MyInstants and SoundButtonsWorld inside the app. Pick a source, browse *Trending*, a category or search. **▶** previews (only you hear it), choose the target in *ADDING TO*, click **Add**.
- **YouTube & more** (**Ctrl+3**): search YouTube or SoundCloud, or paste a link from YouTube, TikTok, X, Instagram and 1000+ sites. The first time, install **yt-dlp** with one click (and **ffmpeg** and **Deno**, recommended). Click *Download*, set a name, the workspace, an optional start and end (`12.5` or `1:05`), and loudness normalization. Progress shows on the *Downloads* page.
- **REC** records whatever your computer plays. See [chapter 12](#12-recording-your-computers-audio).
- **By hand:** copy files into the workspace folder; they show up on the next start.

Formats: MP3, WAV, OGG, FLAC.

<br>

## 5. Playing sounds

- **Click a pad.** Its LED lights, a progress line runs along the bottom and the waveform lights up as it plays.
- **1 … 9, 0** play the first ten pads (Settings can turn this off).
- **Space** pauses everything, Space again resumes exactly where it was. A paused pad's LED blinks; clicking it resumes it.
- **Esc** stops everything, queue included.
- The **random** button plays a random pad from what is on screen (search and favorites filter apply), never the same twice in a row.
- **Ctrl+F** searches; the **star** toggle shows favorites only; the dropdown sorts by manual order, name, recently added or most played.

If you trigger a sound that is already playing, *Settings → Audio* decides: **Restart** (default), **Overlap** (another copy on top) or **Stop** (a toggle).

Right-click a pad for the full menu: play, pause, add to queue, edit and trim, effects, create variant, set hotkey, favorite, duplicate, show in folder, move, delete.

<br>

## 6. The queue

Want sounds one after another instead of all at once? **Shift+click** pads, or right-click → *Add to queue*. Open the panel with the queue toggle in the toolbar. Turn on *Clicking a pad queues it* and normal clicks and hotkeys queue too.

<p align="center"><img src="screenshots/queue.png" alt="The queue panel" width="92%"></p>

| To | Do this |
|---|---|
| Back / play-pause / skip | The three transport buttons |
| Shuffle what hasn't played | *Shuffle* |
| Loop the whole queue | *Repeat queue* |
| Reorder | Drag a row |
| Jump to a sound | Click its row |
| Remove one | Hover it, click **x** |
| Start over | *Clear queue* |

The bottom of the panel shows the time left.

<br>

## 7. Editing a sound

Right-click a pad → **Edit & trim**.

<p align="center"><img src="screenshots/editor.png" alt="The editor" width="92%"></p>

**The waveform**

- **Drag across it** to select what plays. The rest is dimmed.
- **Drag the white handles** to adjust the start and end.
- **Click anywhere** to play from that point.
- The **round handles at the top** are the fades: drag them inward to fade in and out, right on the wave.
- **Mouse wheel** zooms around the pointer; **Shift + wheel** scrolls; the buttons above zoom in, out, to everything, or to the cut. The strip under the ruler shows where you are; drag it to move.
- The **magic wand** cuts the silence at both ends. The **undo arrow** resets the cut.

**Under the waveform**

- **Play** (or **Space**) and **Loop preview**, which keeps your cut playing while you tweak it.
- **Start** and **End**: type exact times, nudge them 10 ms with the arrows (100 ms with Shift), or snap them to where the sound is playing right now.

**The tabs**

- **Sound:** volume (up to 200%), speed (0.5x to 2x, changes the pitch too), fade in, fade out, loop until stopped.
- **Effects:** the effect chain, in the next chapter.
- **Pad:** color, hotkey, and facts: the file, plays, time played, how many pads use the file, measured loudness.

**Undo everything.** Every finished change is a step. **Ctrl+Z** undoes, **Ctrl+Shift+Z** or **Ctrl+Y** redoes, or use the arrows in the editor header.

**Nothing touches your file.** Cut, speed, fades, loop and effects are applied while the sound plays. When you want the cut in the audio for good, **Save cut to file** writes it with ffmpeg (and normalizes loudness if that is on for downloads). If other variants use the same file, this pad gets its own file and the others keep the original.

<br>

## 8. Effects, presets and automation

Right-click a pad → **Effects** (or the *Effects* tab in the editor). Everything plays live: change something while the sound plays and you hear it immediately.

<p align="center"><img src="screenshots/effects.png" alt="The effect chain" width="92%"></p>

**Presets.** The chips at the top are one-click starting points: Demonic, Chipmunk, Robot, Radio, Cave, Underwater, Blown out, Ghost, Lo-fi, Echo, Power down, Riser. Clicking one replaces the chain and plays the sound so you hear it.

**Building a chain.** *Add effect* opens the list of twelve effects (each can be in the chain once). The chain runs in order, up to eight effects. On each card:

- the switch turns it on and off without losing its settings,
- the arrows move it earlier or later in the chain,
- **x** removes it,
- each parameter has a slider and a reset button.

| Effect | What it does |
|---|---|
| Pitch | Higher or lower, same speed |
| Low-pass / High-pass | Muffled / thin |
| Radio / phone | Old radio, phone call |
| Distortion | Crunchy, blown out |
| Bitcrusher | 8-bit, retro game |
| Echo / Reverb | Repeats / room, hall, cave |
| Chorus / Tremolo | Wide and wobbly / pulsing volume |
| Robot | Metallic ring modulation |
| Gain | Louder or quieter |

**Automation.** Next to every parameter there is a small chart button. Turn it on and a second slider appears, *At the end*. The parameter glides from the first value to the second over the sound. Try: pitch from 0 to −12 plus a low-pass from 18 kHz down to 300 Hz, the "power down" sound of a dying machine. That is exactly the *Power down* preset.

**Compare** turns the chain off while you listen, so you can hear the difference. **Clear** empties the chain.

**Your own presets.** Type a name in *Name for a new preset* and **Save**. It appears with the built-in ones on every pad. The **x** on a preset chip deletes it.

**Save** applies the chain to the pad; *Cancel* (or closing the editor) puts back what it had.

<br>

## 9. Variants: one file, many pads

A variant is a second pad that plays **the same file** with its own name, cut, settings and effects. Perfect for "BRUH" and "BRUH (Demonic)" side by side, without a second copy of the audio.

- Right-click a pad → **Create variant**, or **Create variant** at the bottom of the editor.
- The variant is created next to the original and opens on the *Effects* tab.
- Variants are tagged **VAR**. Deleting one keeps the file as long as another pad uses it; moving one to another workspace copies the file.

*Duplicate* is different: it makes an independent copy of the file.

<br>

## 10. The mixer

The mixer toggle in the toolbar docks a small mixing desk under the pads.

- **Master strip** (left): the master fader and meter, **FADE** (fades everything out), **STOP**, and the fade length (click it to cycle 0.5 / 1 / 1.5 / 3 / 5 seconds).
- **One strip per sound playing:** its name, **M** (mute), **F** (fade it out), **■** (stop it), an LED meter of its output after effects, and a **fader** from 0 to 200% with a mark at 100%. Below, the time left, or LOOP / PAUSE.

The fader changes this play only. The pad's own volume is in the editor.

When the mixer is closed, a small green dot on its toggle tells you something is playing.

<br>

## 11. Stage mode

Press **F11**, or **STAGE** in the header.

<p align="center"><img src="screenshots/stage.png" alt="Stage mode" width="92%"></p>

- The whole window becomes the soundboard: huge pads, hotkeys you can read from across the room, a LED per pad.
- The **ON AIR** strip lists what is playing; click one to stop just that sound. Right-clicking a pad stops it too.
- The mixer sits at the bottom (toggle it with the sliders button).
- **STOP EVERYTHING** is the big red button. Esc does the same.
- Workspace chips at the top switch workspaces (when you have more than one).
- Number keys and hotkeys work as usual. **F11** or the minimize button leaves.

*Settings → Appearance → Stage mode goes full screen* decides whether it takes the whole monitor.

<br>

## 12. Recording your computer's audio

Something funny just played in a video or a game? Catch it. Click **REC** in the header.

<p align="center"><img src="screenshots/recorder.png" alt="The recorder" width="80%"></p>

1. **Source:** *Computer audio (what you hear)*, the default microphone, or any input device.
2. Click the round red button. The timer runs, the meter moves and the waveform draws itself. Play what you want to catch.
3. Click again to stop. *Cut silence at the start and end automatically* already trimmed the dead air; drag the red handles to fine-tune.
4. Name it, choose the workspace, **Add to soundboard**. It is saved as WAV and opens in the editor.

Closing the dialog does not lose a recording: it waits there until you add or discard it. *Record again* starts over. Recordings go up to 10 minutes.

On Linux "computer audio" is the monitor of your default output (PipeWire or PulseAudio). On Windows it is a WASAPI loopback of the default output.

<br>

## 13. Playing into Discord (virtual microphone)

Every sound plays twice at the same time: in **your headphones** and into a **virtual microphone** that Discord, games and call apps can use as input.

**Linux**

1. *Settings → Virtual microphone*.
2. Keep *Mix my real microphone in* on, so people still hear your voice.
3. **Create virtual mic**. Status turns green.
4. Discord → *User Settings → Voice & Video → Input Device* → **WooferSoundPad Mic**.
5. Play a pad. The sidebar says *Virtual mic on*.

With your mic mixed in, *Settings → Virtual microphone* also has **My voice volume** (0–150%) and **Mute my voice**; the mic button in the sidebar mutes you in one click, and there is a hotkey for it. After a reboot, click *Create virtual mic* again. It needs `pactl` (`pipewire-pulse` or PulseAudio).

**Windows**

1. Install **VB-Cable** (*Get VB-Cable* in *Settings → Virtual microphone*) as administrator, reboot.
2. *Settings → Virtual microphone* says *VB-Cable detected*: click **Use it**.
3. Discord input device: **CABLE Output (VB-Audio Virtual Cable)**.
4. To keep your voice: Windows *Sound settings → Recording* → your mic → *Properties → Listen* → *Listen to this device* through **CABLE Input**.

**Volumes:** *Settings → Audio* has separate volumes for the headphones, the virtual mic and previews. If effects come through choppy, turn down Discord's noise suppression.

<br>

## 14. Hotkeys

**Per sound:** right-click → *Set hotkey*, press a combination like `F5`, `Ctrl+Shift+1` or `Alt+Num3`. Conflicts are flagged. Hotkeys belong to the active workspace.

**App-wide**, in *Settings → Hotkeys*: stop all (`Pause` by default), pause / resume, next in queue, random sound, mute my voice.

**While gaming:** with *Global hotkeys* on they work while another app has focus, on Windows and on Linux X11.

**Linux on Wayland:** apps cannot listen to keys globally, so make a desktop shortcut that runs a command:

```sh
WooferSoundPad --play "bruh"     # play a sound from the active workspace
WooferSoundPad --queue "bruh"    # queue it
WooferSoundPad --stop            # stop everything
WooferSoundPad --pause           # pause / resume
WooferSoundPad --next            # next in the queue
WooferSoundPad --random          # a random sound
WooferSoundPad --mute-voice      # mute / unmute your voice
```

KDE: *System Settings → Keyboard → Shortcuts → Add New → Command or Script*. GNOME: *Settings → Keyboard → Custom Shortcuts*. Hyprland: `bind = SUPER, F1, exec, WooferSoundPad --play "bruh"`. Sway: `bindsym $mod+F1 exec WooferSoundPad --play "bruh"`.

<br>

## 15. OBS, Stream Deck and your phone

*Settings → OBS & Stream Deck* → turn on **Local control server**. The section shows three links, each with a copy button.

<p align="center"><img src="screenshots/integrations.png" alt="OBS and Stream Deck settings" width="92%"></p>

- **OBS overlay.** In OBS: *Sources → + → Browser*, paste the overlay link, size it like 600×400. It is transparent and shows each sound while it plays, with its color and a progress bar. Add `&align=right` to stack it on the right, `&scale=1.5` to make it bigger.
- **Web deck.** Open it in a browser and you get your pads, workspace switching, FADE and STOP. To use it on your phone, turn on *Allow other devices on the network* and replace `127.0.0.1` with your PC's IP address.
- **Stream Deck and friends.** Any button that can open a URL can play a sound. Use the command link and change the end: `name=bruh` plays BRUH, `/api/stop` stops everything, `/api/fade` fades everything, `/api/random`, `/api/next`, `/api/stage`. In Stream Deck use a *Website* action with *Access in background*, or a web-request plugin.

<p align="center"><img src="screenshots/web-deck.png" alt="The web deck" width="80%"></p>

The key in the links keeps random web pages from triggering your sounds. *New key* invalidates old links if one leaks.

<br>

## 16. Even volumes and statistics

**Even volumes.** Sounds from the internet come at every volume. *Settings → Audio → Even out the library's volume* measures each file once and plays them all at the same loudness (the *target loudness* slider, −16 dB by default). It never pushes a sound into clipping, it never changes your files, and switching it off puts everything back. The status line shows how many sounds of the workspace are measured; the editor's *Pad* tab shows each one's loudness and the gain applied.

**Statistics** (**Ctrl+5**): total plays, time played, plays today and your streak, how many of your sounds you actually use, the meme ranking, the last 14 days as a chart, and the history of every play. Switch between all workspaces and this one; *Clear history* wipes the history and the chart.

<p align="center"><img src="screenshots/stats.png" alt="Statistics" width="92%"></p>

<br>

## 17. Settings, themes and portable mode

| Section | Inside |
|---|---|
| Appearance | 14 themes with live previews, language, interface size (75–200%), animations, pad size, hotkeys on pads, waveforms on pads, stage mode full screen |
| Audio | Headphones output, virtual mic output, their volumes, preview volume, what retriggering does, library normalization |
| Virtual microphone | Create / remove it (Linux) with voice volume and mute, or VB-Cable (Windows) |
| Hotkeys | Global hotkeys on / off, the app-wide hotkeys, number keys, the Wayland command |
| OBS & Stream Deck | The local control server, port, network access, links, new key |
| Library | Library folder, cache size and *Clear cache* |
| Downloads & tools | yt-dlp, ffmpeg, Deno; download format, normalization, max clip length |
| About | Version, project page, the tour |

**Portable mode:** put an empty `portable.txt` next to the executable (the Windows portable zip already has it). Settings, tools, cache, statistics and your sound library then live in a `data` folder beside it. Delete `portable.txt` to go back.

<br>

## 18. Handy tips

- **Panic:** Esc inside the app, your stop-all hotkey anywhere, the big red button in stage mode.
- **Same sounds everywhere:** point *Settings → Library* at a synced folder (Syncthing, Dropbox, Nextcloud).
- **Too loud for you, fine for them:** the headphones and virtual mic volumes are separate.
- **A sound that is almost right:** make a variant and experiment; the original stays untouched.
- **Free up space:** *Settings → Library → Clear cache* removes previews and thumbnails.
- **Something off?** The [FAQ](../README.md#faq), or [open an issue](https://github.com/RshaCuDeVidro/WooferSoundPad/issues).

Have fun, and be kind to your friends' ears.
