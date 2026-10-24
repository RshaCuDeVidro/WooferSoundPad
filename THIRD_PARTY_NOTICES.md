# Third-party notices

WooferSoundPad is released under the [MIT License](LICENSE). It is built on top
of the open-source components listed below, which keep their own licenses.

## Compiled into the executable

| Component | Version | Author(s) | License | Location in this repo |
|---|---|---|---|---|
| [raylib](https://github.com/raysan5/raylib) | 6.2 | Ramon Santamaria and contributors | zlib | `vendor/raylib/` ([LICENSE](vendor/raylib/LICENSE)) |
| [GLFW](https://www.glfw.org/) (via raylib's `rglfw.c`) | 3.x | Marcus Geelnard, Camilla Löwy | zlib | `vendor/raylib/external/glfw/` ([LICENSE.md](vendor/raylib/external/glfw/LICENSE.md)) |
| [miniaudio](https://miniaud.io/) (incl. dr_wav, dr_mp3, dr_flac) | 0.11.25 | David Reid | Public Domain (Unlicense) **or** MIT No Attribution | `vendor/raylib/external/miniaudio.h` (license at the end of the file) |
| [stb_vorbis](https://github.com/nothings/stb) | 1.22 | Sean Barrett | MIT **or** Public Domain | `vendor/raylib/external/stb_vorbis.c` |
| stb_image, stb_truetype, stb_rect_pack, stb_image_resize2 (used by raylib) | — | Sean Barrett and contributors | MIT **or** Public Domain | `vendor/raylib/external/` |
| sinfl / sdefl, qoi and the other single-header helpers shipped with raylib | — | see each header | MIT / zlib / Public Domain (see each header) | `vendor/raylib/external/` |
| [tinyfiledialogs](https://sourceforge.net/projects/tinyfiledialogs/) | 3.22.1 | Guillaume Vareille | zlib | `vendor/tinyfiledialogs/` (license in the file header) |

## Embedded assets

| Asset | Author(s) | License | Location |
|---|---|---|---|
| [Inter](https://github.com/rsms/inter) (Regular, SemiBold, Bold) | The Inter Project Authors | SIL Open Font License 1.1 | `assets/fonts/` ([OFL.txt](assets/fonts/OFL.txt)) |
| [Outfit](https://github.com/Outfitio/Outfit-Fonts) (Bold) | The Outfit Project Authors | SIL Open Font License 1.1 | `assets/fonts/` ([OFL.txt](assets/fonts/OFL.txt)) |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) (Medium, Bold) | The JetBrains Mono Project Authors | SIL Open Font License 1.1 | `assets/fonts/` ([OFL.txt](assets/fonts/OFL.txt)) |
| [Lucide](https://lucide.dev/) icon font | Lucide Icons and Contributors (some icons derived from Feather, © Cole Bemis) | ISC (Feather-derived icons: MIT) | `assets/fonts/lucide.ttf` ([LUCIDE-LICENSE.txt](assets/fonts/LUCIDE-LICENSE.txt)) |

The WooferSoundPad logo, icon and banner (`assets/*.svg`, `assets/*.png`,
`assets/icon.ico`) are part of this project and covered by its MIT license.

## Downloaded at runtime (not bundled)

These tools are **not** shipped with WooferSoundPad. If they are not already
installed on your system, the app offers to download the official builds into
its data folder when you click **Install** in *Settings → Downloads & tools*.
They run as separate programs and keep their own licenses.

| Tool | Used for | License | Downloaded from |
|---|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | YouTube / SoundCloud search and downloads from 1000+ sites | Unlicense (the standalone builds bundle components under other licenses, see the yt-dlp repo) | `github.com/yt-dlp/yt-dlp` releases |
| [FFmpeg](https://ffmpeg.org/) | Converting, trimming and normalizing audio | GPL v3 (the "gpl" builds) | `github.com/yt-dlp/FFmpeg-Builds` releases |
| [Deno](https://deno.com/) | JavaScript runtime used by yt-dlp for YouTube | MIT | `github.com/denoland/deno` releases |

## System programs used when present

`curl` (HTTP), `tar`, `pactl` (PulseAudio/PipeWire virtual microphone) and
`zenity` / `kdialog` (file dialogs, through tinyfiledialogs) are invoked as
external programs and are not distributed with WooferSoundPad.

## Online content

Sounds found through *Explore* come from [MyInstants](https://www.myinstants.com)
and [SoundButtonsWorld](https://soundbuttonsworld.com), and media found through
*YouTube & more* comes from the respective platforms. That content belongs to
its owners and is not covered by this project's license.

---

## Full license texts

### SIL Open Font License 1.1 (Inter, Outfit, JetBrains Mono)

```text
Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
    -> applies to: Inter-Regular.ttf, Inter-SemiBold.ttf, Inter-Bold.ttf
Copyright 2021 The Outfit Project Authors (https://github.com/Outfitio/Outfit-Fonts)
    -> applies to: Outfit-Bold.ttf
Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono)
    -> applies to: JetBrainsMono-Medium.ttf, JetBrainsMono-Bold.ttf

Files are the Latin subsets distributed by Fontsource (https://fontsource.org).

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```

### ISC License (Lucide) and MIT License (Feather-derived icons)

```text
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

---

The following Lucide icons are derived from the Feather project:

airplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out

The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### zlib License (raylib)

```text
Copyright (c) 2013-2026 Ramon Santamaria (@raysan5)

This software is provided "as-is", without any express or implied warranty. In no event 
will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial 
applications, and to alter it and redistribute it freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not claim that you 
  wrote the original software. If you use this software in a product, an acknowledgment 
  in the product documentation would be appreciated but is not required.

  2. Altered source versions must be plainly marked as such, and must not be misrepresented
  as being the original software.

  3. This notice may not be removed or altered from any source distribution.
```

### zlib License (GLFW)

```text
Copyright (c) 2002-2006 Marcus Geelnard

Copyright (c) 2006-2019 Camilla Löwy

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would
   be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not
   be misrepresented as being the original software.

3. This notice may not be removed or altered from any source
   distribution.

```

### zlib License (tinyfiledialogs)

```text
Copyright (c) 2014 - 2025 Guillaume Vareille http://ysengrin.com

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
```

### miniaudio and stb

miniaudio is dual-licensed as Public Domain (Unlicense) or MIT No Attribution;
stb libraries are dual-licensed as MIT or Public Domain. The full texts are at
the end of `vendor/raylib/external/miniaudio.h` and of each `stb_*` file.

Local change: in `ma_slot_allocator_alloc` / `ma_slot_allocator_free` the bit
shifts `1 << n` were changed to `(ma_uint32)1 << n`, so shifting into bit 31 is
well-defined (it tripped the undefined-behavior sanitizer of debug builds).

### Freeverb

The reverb in `src/c/woof_dsp.h` follows the public-domain Freeverb design by
Jezar at Dreampoint (comb and allpass tunings, damping and room-size mapping).
No Freeverb source code is included.
