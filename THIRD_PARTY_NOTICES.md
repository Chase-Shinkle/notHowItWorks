# Third-party notices

This file is shipped at the root of the `.love` package.

## Code

| Component | Path | License | Notice |
|-----------|------|---------|--------|
| g3d (groverburger) | `g3d/` | MIT | Full text in `g3d/init.lua` (`_LICENSE`), Copyright (c) groverburger, https://github.com/groverburger/g3d |
| push v0.4 | `lib/push.lua` | MIT | Full text in the file header, Copyright (c) 2020 Ulysse Ramage |
| hump.class | `lib/class.lua` | MIT-style | Full text in the file header, Copyright (c) 2010-2013 Matthias Richter |
| knife | `lib/knife/` | MIT (upstream: https://github.com/airstruck/knife) | **No license text is vendored with these files.** Copy the upstream LICENSE into `lib/knife/` before a public release. |

The game runs on LÖVE 11.5 (zlib license), which is not included in the
`.love` file. Players install it separately.

## Art

| Asset | Path | Status |
|-------|------|--------|
| "Farming - Crops Pack 017" sprites | `graphics/Farming - Crops Pack 017/` | Supplied by the project owner. **No license file is included in the repository.** Confirm that the pack's license allows redistribution in a game build before a public release. |
| Backrooms wallpaper, carpet and ceiling-tile textures | `graphics/backrooms/` | Extracted byte-for-byte from the owner-supplied `models/Backrooms.glb` (made with Blender glTF I/O) by `tools/extract_glb_textures.py`. **The model's source and license are not recorded in the repository.** Confirm before a public release. |
| `SaH1Outline.ttf` display font (title, buttons, ending headline) | `fonts/SaH1Outline.ttf` | Supplied by the project owner. **Licence: UNCONFIRMED. Author: UNCONFIRMED.** Neither the author nor the licence terms are recorded; do not ship publicly until both are confirmed with the supplier and this entry is completed. The game falls back to the built-in font if the file is absent. |

## Audio

None. No sound files were supplied (`sounds/` does not exist), so the game is
silent. It plays a silent placeholder wherever a sound would go.
