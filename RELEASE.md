# Release notes / how to play

## Running

1. Install LÖVE **11.5** (https://love2d.org).
2. Run the package:
   - Linux: `love not-how-it-works.love`
   - Windows: drag `not-how-it-works.love` onto `love.exe`, or run
     `"C:\Program Files\LOVE\love.exe" not-how-it-works.love`
   - macOS: `open -n -a love not-how-it-works.love`, or
     `/Applications/love.app/Contents/MacOS/love not-how-it-works.love`

The window is 800x800 and resizable. A GPU with OpenGL 2.1+ and a 24-bit depth
buffer is needed for the 3D part.

## Controls

Start / ending screens: **Enter**.

Farm (2D):
- Move: **WASD** / **arrow keys** (one tile per press, hold to repeat).
- Use the highlighted tile: **E** / **Space** / **Enter** (plant on an empty
  plot, harvest a ripe crop, sell to the villager). Left click on a plot or the
  villager does the same.
- Seeds: **1-3** select a type, **Tab** / **Q** cycles; click a seed slot in
  the top bar.
- Plant, wait about 12 s, harvest, sell to the villager... then keep selling.

Backrooms (3D, first person):
- Look: **mouse** (captured on entry). Walk: **WASD** / **arrow keys**.
- Plant the selected seed on the nearest soil plot: **E** / **Enter** / left
  click.
- Seeds: **1-3** select, **Q** / **Tab** cycle.
- Beanstalk: walk forward into it to climb, back to climb down, sideways to
  step off at the top. Pumpkins fill pits. Vines bridge gaps.
- **R**: reset the room (crops removed, seeds restored). Falling into a pit
  or gap puts you back at the room start.
- **Esc**: free the mouse; click to capture it again.

Debug mode is **off** in this build: F1 does nothing and the HUDs show no
debug text. It is for development only and is turned on with an explicit
launch flag, `--debug` (for example `love . --debug` from the source tree, or
`love not-how-it-works.love --debug`). With it, **F1** skips ahead (start ->
farm -> backrooms -> next room -> ending -> start) and the HUDs show a debug
line. `tools/package.sh` never turns it on.

## Building the package

From the repo root:

```
sh tools/package.sh
```

writes `dist/not-how-it-works.love` (ignored by git) and prints its sha256.
The build is reproducible: the same source tree gives the same bytes.

Verify the artifact (needs `xvfb-run` on a headless machine):

```
xvfb-run -a timeout 8 love dist/not-how-it-works.love                       # expect exit 124, no "Error"
xvfb-run -a timeout 8 love dist/not-how-it-works.love --placeholder-assets  # same
xvfb-run -a -s '-screen 0 1024x1024x24' love dist/not-how-it-works.love --autotest
```

The last one plays the whole game from the packaged files with scripted
input and prints `[autotest] N checks, 0 failed`. `tests/autotest.lua` is the
only test file in the package. It loads only with `--autotest`.

## Known gaps

- No sound: no audio files were supplied, so every sound is a silent
  placeholder.
- Third-party art licenses are not recorded in the repo. See
  `THIRD_PARTY_NOTICES.md` before publishing.
