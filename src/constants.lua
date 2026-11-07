-- Window and virtual dimensions
WINDOW_WIDTH = 800
WINDOW_HEIGHT = 800

VIRTUAL_WIDTH = 320
VIRTUAL_HEIGHT = 320

-- Debug helpers: when enabled, DEBUG_ADVANCE_KEY jumps to the next state
-- (start -> farm -> backrooms rooms -> ending -> start) and the HUDs show a
-- debug line, so the flow can be checked without playing through it.
-- Off by default, so the packaged release never has them; development runs
-- opt in with the `--debug` launch flag (`love . --debug`), parsed in
-- src/Dependencies.lua with the other launch flags.
DEBUG_MODE = false
DEBUG_ADVANCE_KEY = 'f1'

-- Seed types shared by the farm and the backrooms, in display order.
SEED_TYPES = {'beanstalk', 'pumpkin', 'vine'}

-- Player-facing names of the seed types. Internal keys (game data, room
-- allotments, art keys) never change; every name the player reads goes
-- through SeedName() (src/Util.lua), so the vine type reads as "corn".
SEED_DISPLAY_NAMES = {
    beanstalk = 'beanstalk',
    pumpkin = 'pumpkin',
    vine = 'corn',
}

-- Seeds the player owns at the start of a new run.
STARTING_SEEDS = {
    beanstalk = 2,
    pumpkin = 2,
    vine = 2,
}

-- 2D farm ---------------------------------------------------------------------
-- The farm is a grid of FARM_TILE-pixel tiles over the 320x320 virtual screen.
-- Tile coordinates are 1-based (col, row). Row 1 is the HUD bar and the last
-- row is the hint bar, so the walkable field is rows 2 .. FARM_ROWS - 1.
FARM_TILE = 32
FARM_COLS = VIRTUAL_WIDTH / FARM_TILE      -- 10
FARM_ROWS = VIRTUAL_HEIGHT / FARM_TILE     -- 10
FARM_FIELD_TOP = 2
FARM_FIELD_BOTTOM = FARM_ROWS - 1

-- Plot rectangle (2 rows, so every plot is reachable from above or below).
FARM_PLOTS = {col = 2, row = 4, cols = 3, rows = 2}

-- The villager stands on this tile; the player sells by facing/clicking it.
FARM_VILLAGER = {col = 8, row = 4}

-- Player start: directly below a plot and facing it, so the first key press
-- tills it (the next one plants).
FARM_PLAYER_START = {col = 3, row = 6, facing = 'up'}

-- World dressing (tiles are {col, row}). Solid pieces block movement; the
-- path and the scattered tufts and stones are ground decoration only.
-- Layout rules (checked by tests): nothing on the HUD/hint rows, the player
-- start, a plot, the villager or the stall; the fence flanks the plot block
-- on its left and right only (row 3 above and row 6 below stay open), so
-- every plot, the villager and the stall keep a walkable neighbour reachable
-- from the start; the stall keeps all four neighbours free.
FARM_DECOR = {
    fence = {{1, 4}, {1, 5}, {5, 4}, {5, 5}},
    path = {{4, 6}, {5, 6}, {6, 6}, {7, 6}, {7, 5}, {7, 4}, {7, 7}},
    -- barn: drawn at native size, left edge on `col`, bottom on the bottom
    -- edge of `row`, so its roof sits behind the HUD bar; `blocks` tiles
    barn = {col = 8, row = 3, blocks = {{8, 2}, {9, 2}, {10, 2}, {8, 3}, {9, 3}, {10, 3}}},
    well = {{10, 7}},
    bushes = {{6, 2}, {1, 7}, {10, 4}, {5, 9}},
    pond = {{9, 9}, {10, 9}, {10, 8}},
    -- ground variation: fixed seed, chance per free grass tile
    groundSeed = 1337,
    tuftChance = 0.45,
    stoneChance = 0.12,
    -- second layer on free grass tiles: extra tufts, flowers, leafy plant
    -- tiles (pack 'Tile -Plant') and small bush sprites (non-blocking)
    extraTufts = 2,
    flowerChance = 0.5,
    plantTileChance = 0.16,
    shrubChance = 0.14,
}
-- Ambient motion: sway angle (x-skew), its speed, and pond shimmer speed.
FARM_SWAY_SKEW = 0.08
FARM_SWAY_SPEED = 1.7
FARM_POND_SHIMMER_SPEED = 1.2

-- Growth: a crop moves through FARM_GROWTH_STAGES visible stages (1 = seeds,
-- last = mature), one stage every FARM_STAGE_TIME seconds of full-rate growth
-- (12 s in total). A watered crop grows at the full rate; an unwatered one at
-- FARM_UNWATERED_RATE of it (24 s in total). Growth is advanced by elapsed
-- time (Farm.advance), so watering mid-growth keeps the progress made.
FARM_GROWTH_STAGES = 5
FARM_STAGE_TIME = 3
FARM_UNWATERED_RATE = 0.5

-- Coins paid by villagers per harvested crop.
CROP_VALUES = {
    beanstalk = 3,
    pumpkin = 5,
    vine = 4,
}

-- Seed stall: the player buys one seed of the selected type per use, from the
-- stall on this tile (face it and press E, or click it). Each price is below
-- that crop's sale value (a test checks), so plant -> harvest -> sell -> rebuy
-- nets 1 coin. Buying never affects the break (src/states/game/FarmState.lua).
FARM_SHOP = {col = 8, row = 7}
SEED_PRICES = {
    beanstalk = 2,
    pumpkin = 4,
    vine = 3,
}

-- Grid movement: one tile per press; holding a key repeats after a delay.
FARM_MOVE_REPEAT_DELAY = 0.25
FARM_MOVE_REPEAT_INTERVAL = 0.12

-- Key bindings (any key in a list works).
FARM_KEYS = {
    up = {'up', 'w'},
    down = {'down', 's'},
    left = {'left', 'a'},
    right = {'right', 'd'},
    interact = {'e', 'space', 'return', 'kpenter'},
    nextSeed = {'tab', 'q'},
}

-- Farm top bar (virtual px): left margin, slot top and height, seed slot
-- width (bag icon + key number over 'x999'), produce slot width (icon +
-- '999'), icon sizes, the gap around the divider and the coin icon, and the
-- alpha of empty slots. A layout test checks that nothing overlaps with
-- three-digit counts.
FARM_HUD = {
    left = 3, top = 2, height = 24,
    seedSlotW = 40, seedIcon = 14,
    produceSlotW = 31, produceIcon = 12,
    coinIcon = 9, gap = 3,
    emptyAlpha = 0.35,
}

-- Tool icon beside the farmer (px), and the villager's sale hop height (px).
FARM_TOOL_ICON_SIZE = 12
FARM_VILLAGER_HOP = 16

-- Farm game feel (src/Fx.lua) ------------------------------------------------------
-- Particle bursts per action: count, speed (px/s) and life (s) ranges,
-- gravity (px/s^2), size (px), start jitter (px), optional launch angle and
-- spread (radians; omitted = all directions), colours, and shape ('spark'
-- draws a small plus while young).
FX_MAX_PARTICLES = 160
FX_BURSTS = {
    till = {count = 10, speed = {20, 45}, life = {0.35, 0.6}, gravity = 160, size = 2, jitter = 4,
        angle = -math.pi / 2, spread = 1.1,
        colors = {{0.45, 0.3, 0.17, 1}, {0.6, 0.42, 0.24, 1}, {0.35, 0.24, 0.14, 1}}},
    plant = {count = 8, speed = {12, 30}, life = {0.3, 0.55}, gravity = 90, size = 1, jitter = 3,
        angle = -math.pi / 2, spread = 1.2,
        colors = {{0.55, 0.85, 0.35, 1}, {0.85, 0.75, 0.45, 1}}},
    water = {count = 10, speed = {15, 40}, life = {0.3, 0.55}, gravity = 140, size = 1, jitter = 6,
        angle = -math.pi / 2, spread = 1.3,
        colors = {{0.55, 0.8, 1, 1}, {0.8, 0.95, 1, 1}, {0.35, 0.6, 0.95, 1}}},
    harvest = {count = 12, speed = {20, 55}, life = {0.4, 0.7}, gravity = 120, size = 2, jitter = 4,
        colors = {{0.55, 0.9, 0.35, 1}, {1, 0.9, 0.35, 1}, {0.9, 1, 0.7, 1}}},
    sell = {count = 12, speed = {20, 50}, life = {0.4, 0.7}, gravity = 110, size = 1, jitter = 4,
        angle = -math.pi / 2, spread = 1.2, shape = 'spark',
        colors = {{1, 0.88, 0.3, 1}, {1, 0.97, 0.7, 1}}},
    buy = {count = 8, speed = {15, 35}, life = {0.3, 0.55}, gravity = 80, size = 1, jitter = 4,
        angle = -math.pi / 2, spread = 1.3, shape = 'spark',
        colors = {{0.7, 1, 0.6, 1}, {1, 1, 1, 1}}},
    coins = {count = 6, speed = {10, 25}, life = {0.3, 0.5}, gravity = 40, size = 1, jitter = 3,
        shape = 'spark', colors = {{1, 0.9, 0.35, 1}, {1, 1, 0.8, 1}}},
    mature = {count = 8, speed = {8, 20}, life = {0.4, 0.7}, gravity = -10, size = 1, jitter = 6,
        shape = 'spark', colors = {{1, 1, 0.75, 1}, {1, 0.95, 0.45, 1}}},
}
FX_POP_TIME = 0.25          -- pop bounce length (s)
FX_POP_SCALE = 0.25         -- extra scale at the top of a pop
FX_SQUASH_TIME = 0.4        -- growth-stage squash length (s)
FX_SQUASH_AMOUNT = 0.25     -- 1.25x wide / 0.75x tall at the start
FX_POPUP_LIFE = 1.2         -- floating text (s)
FX_FLY_TIME = 0.6           -- harvested crop flight to the HUD (s)
FX_FLY_ARC = 24             -- flight arc height (px)
FX_TICKER_RATE = 6          -- coin ticker: fraction of the gap closed per second
FX_TICKER_MIN_SPEED = 8     -- coin ticker: minimum coins per second
FX_COIN_TICK_INTERVAL = 0.06 -- minimum seconds between coin tick sounds
FARM_SFX_VOLUME = 0.5       -- volume of the generated farm sound effects

-- Farm day cycle ---------------------------------------------------------------
-- A day lasts FARM_DAY_LENGTH seconds of farm time (paused during the break)
-- and runs dawn -> day -> dusk -> night; the day counter goes up at each new
-- dawn (phase 0). A new farm starts at FARM_DAY_START_PHASE, in full
-- daylight. FARM_DAY_TINTS are keyframes {phase, {r, g, b}} multiplied over
-- the farm view (by the shader, or by a fallback overlay); night stays at
-- about 0.7 brightness so the farm is still readable.
FARM_DAY_LENGTH = 90
FARM_DAY_START_PHASE = 0.2
FARM_DAY_TINTS = {
    {0.00, {1.00, 0.84, 0.72}},     -- dawn: warm
    {0.10, {1.00, 0.95, 0.88}},
    {0.18, {1.00, 1.00, 1.00}},     -- day: neutral
    {0.55, {1.00, 1.00, 1.00}},
    {0.66, {1.00, 0.80, 0.62}},     -- dusk: orange
    {0.76, {0.64, 0.68, 0.92}},     -- night: cool and darker
    {0.92, {0.64, 0.68, 0.92}},
    {1.00, {1.00, 0.84, 0.72}},     -- back to dawn
}

-- Farm look pipeline (shaders/farm.glsl + farm_blur.glsl via src/FarmShader.lua)
-- Every strength is a uniform, so the look is tuned here, not in the GLSL.
-- Setting one to 0 removes that effect only. Tuned (task 5.4) after the look
-- review: the in-focus band stays pixel-identical in sharpness to the pass
-- off (measured on real captures, see verification.md); FARM_DAY_LENGTH
-- stays 90 s so a first plant-harvest-sell loop sees dusk.
FARM_FX_SUN = 0.10                      -- warm multiply toward FARM_FX_SUN_COLOR (by day)
FARM_FX_SUN_COLOR = {1.0, 0.86, 0.58}   -- golden
FARM_FX_SUN_GLOW = 0.30                 -- warm glow from the sun corner (by day)
FARM_FX_SUN_POS = {-0.18, -0.05}        -- light source, uv, beyond the top-left corner
FARM_FX_SHAFT = 0.30                    -- diagonal light shafts fanning from the sun (by day)
FARM_FX_SHAFT_SPEED = 0.05              -- shaft drift speed
FARM_FX_BLOOM = 0.55                    -- soft glow from bright / strongly coloured areas
FARM_FX_BLOOM_THRESHOLD = 0.66          -- brightness where bloom starts
FARM_FX_GLIMMER = 0.4                   -- sparkle on very bright pixels (ripe crops, pond)
FARM_FX_GLIMMER_THRESHOLD = 0.8         -- luminance where glimmer starts
FARM_FX_TILT = 0.7                      -- blur at the very top/bottom edge (0 = all sharp)
FARM_FX_FOCUS_HALF = 0.28               -- fully sharp middle zone, half height (uv): middle 56% of the screen
FARM_FX_FOCUS_RAMP = 0.22               -- smootherstep ramp from the zone to the top/bottom edge (uv)
FARM_FX_SATURATION = 0.22               -- saturation lift (0 = unchanged)
FARM_FX_VIGNETTE = 0.22                 -- corner darkening

-- Ambient life drawn into the scene (so it shares the depth of field):
-- drifting light motes, falling petals and leaves (counts), frozen in the break.
FARM_AMBIENT_MOTES = 22
FARM_AMBIENT_PETALS = 9
FARM_AMBIENT_LEAVES = 6

-- The break (over-sell -> glitch -> fall) ----------------------------------------
-- After the first sale the villager keeps asking for crops. Trying to sell
-- with zero crops (once hasSold is true) starts the break; so does going
-- FARM_IDLE_BREAK_TIME seconds after the most recent sale without an
-- over-sell attempt. Before any sale neither trigger can fire.
FARM_IDLE_BREAK_TIME = 45

-- Seconds between the villager's repeated requests once the player is out of
-- crops after a sale.
FARM_VILLAGER_NAG_INTERVAL = 4
FARM_VILLAGER_REQUESTS = {
    'More! Sell me more!',
    "I'll take another!",
    'Just one more crop?',
    'Sell me one more!',
}

-- Glitch sequence timing (seconds): shake + corruption ramp up, then the
-- farmer falls out of the farm, then the game changes to the backrooms.
FARM_BREAK_GLITCH_TIME = 1.6
FARM_BREAK_FALL_TIME = 1.4
FARM_BREAK_SHAKE = 6                -- peak screen-shake offset, virtual px
FARM_BREAK_CORRUPTION_BLOCKS = 28   -- corrupted blocks drawn at full glitch

-- Seeds the player is topped up to (per type) on arriving in the backrooms.
-- Room 1 (tutorial) is finished with a single beanstalk seed on its demo
-- crop; this must equal Room 1's allotment in src/rooms.lua (a test checks).
FIRST_ROOM_MIN_SEEDS = {
    beanstalk = 1,
}

-- 3D backrooms ------------------------------------------------------------------
-- World units are metres, z is up (g3d.camera's default). The player is a
-- vertical capsule whose position is the bottom of the capsule (the feet).
BACKROOMS_PLAYER_RADIUS = 0.3
BACKROOMS_PLAYER_HEIGHT = 1.7
BACKROOMS_EYE_HEIGHT = 1.55
BACKROOMS_WALK_SPEED = 4            -- m/s
BACKROOMS_GRAVITY = 18              -- m/s^2
BACKROOMS_TERMINAL_SPEED = 25       -- max fall speed, m/s
-- A contact whose normal has a z component above this supports the player
-- (floor / top face); below -this it is a ceiling.
BACKROOMS_GROUND_NORMAL = 0.6
-- Collision tuning: frames longer than MAX_DT are clamped, each move is split
-- so no sub-step travels more than MAX_STEP (well under the radius, so the
-- capsule cannot tunnel through 0.2 m walls), and push-out is repeated up to
-- RESOLVE_ITERATIONS times per sub-step so corners settle.
BACKROOMS_MAX_DT = 1 / 20
BACKROOMS_MAX_STEP = 0.1
BACKROOMS_RESOLVE_ITERATIONS = 4
BACKROOMS_SKIN = 0.001              -- extra push-out so contacts don't re-trigger
-- Falling below a room's killZ (default) respawns the player at its spawn.
BACKROOMS_KILL_Z = -10

-- Climbing a grown beanstalk (see PlayerController): vertical speed, and how
-- far beyond a climb volume's bottom/top the feet still count as inside it.
BACKROOMS_CLIMB_SPEED = 2.5         -- m/s
BACKROOMS_CLIMB_MARGIN = 0.05

-- Planting in the backrooms: the nearest fixed plot within this horizontal
-- distance of the player's feet, and within this height difference.
BACKROOMS_PLANT_RANGE = 1.8
BACKROOMS_PLANT_HEIGHT = 1.6
-- Pit plots (Rooms 2 and 3) set their own, larger `reach` so they can be
-- planted from well back on the floor instead of a thin strip at the rim.
-- The feet fall off the rim 1.26 m from the pit plot's centre (measured by
-- tests/rim.lua), so 3.8 m gives a plantable floor span of about 2.5 m,
-- including positions 2.0 m back from the rim. The height limit still applies.
BACKROOMS_PIT_PLANT_RANGE = 3.8
-- Uprooting is refused while the player's box is within this distance of the
-- crop's full volume (standing on it, inside it or climbing it).
BACKROOMS_UPROOT_MARGIN = 0.12

-- Key bindings (any key in a list works). Mouse look uses love.mousemoved.
BACKROOMS_KEYS = {
    forward = {'w', 'up'},
    back = {'s', 'down'},
    left = {'a', 'left'},
    right = {'d', 'right'},
    releaseMouse = {'escape'},
    plant = {'e', 'return'},          -- a left click plants too (mouse captured)
    nextSeed = {'q', 'tab'},
    seedSlots = {'1', '2', '3'},      -- select SEED_TYPES[i] directly
    reset = {'r'},
    uproot = {'x'},                   -- remove the crop on the nearest plot
}

-- Procedural backrooms levels (src/LevelGen.lua). Cells are square, CELL m on
-- a side; modules (obstacles) are exactly one cell long.
LEVELGEN_CELL = 6
LEVELGEN_WALL = 0.2                  -- wall / ceiling / floor slab thickness
LEVELGEN_DOOR = 2.4                  -- doorway width between side cells
LEVELGEN_CEILING = 6                 -- ceiling height above a cell's entry floor
LEVELGEN_VOID_Z = -4                 -- bottom of pits and gaps
LEVELGEN_KILL_Z = -0.5
LEVELGEN_MAX_ATTEMPTS = 60           -- derived-seed retries by the self-check (branch sites/optional plots accept ~25-35% of builds)
LEVELGEN_BRANCH_CHANCE = 0.45        -- (legacy spine generator; unused by the maze)
LEVELGEN_LOOP_CHANCE = 0.4           -- chance per candidate same-region cell pair to become a loop
-- Maze (branching-maze-levels sections 1-2). A difficulty row may override
-- `grid` (number or {w, h}), `minPath` and `minTurns`; section 6 tunes them.
LEVELGEN_GRID = 6                    -- default grid is LEVELGEN_GRID x LEVELGEN_GRID cells
LEVELGEN_MIN_PATH = 14               -- critical path length in cells, start and exit included
LEVELGEN_MIN_TURNS = 3               -- turns on the critical path
LEVELGEN_CARVE_MIX = 0.5             -- chance per carve step to extend a random active cell instead of the newest (shorter path, more side branches)
LEVELGEN_MAX_PATH_FRAC = 0.6         -- critical path may use at most this share of the grid cells (rows may override with maxPathFrac)
LEVELGEN_CARVE_TRIES = 12            -- carve retries (derived seeds) before the fallback template
LEVELGEN_ROOM_CHANCE = 0.5           -- per candidate 2x2 block to merge into a large room
LEVELGEN_MAX_ROOMS = 4
LEVELGEN_NARROW_CHANCE = 0.35        -- straight corridor cells narrowed by side slabs
LEVELGEN_NARROW_INSET = 0.5          -- m per side (props hug walls at 0.8, so they stay clear)
LEVELGEN_CEILING_VARIANTS = {-1, -0.5, 0, 0, 0.8, 1.6}   -- added to LEVELGEN_CEILING (non-module cells)
LEVELGEN_ZONE_CELLS = 10             -- about one zone per this many cells (see openspec backrooms-zones-variety-audio)
LEVELGEN_MIN_ZONES = 3
LEVELGEN_BOX_BUDGET = 1500           -- most boxes in one generated level
-- Difficulty table: chain obstacle count and the obstacle types allowed. The
-- level sequence (later section) indexes into it.
LEVELGEN_DIFFICULTY = {
    -- grid / minPath / minTurns are read by LevelGen.build; `branches` is the
    -- minimum optional-branch count (read by the later branch sections).
    -- Rows never shrink in grid area, minPath or branches. minPath >= 21 cells so the
    -- centre-to-centre walk (minPath - 1) * LEVELGEN_CELL / BACKROOMS_WALK_SPEED is >= 30 s
    -- (level-length spec: 'pure walking time at least 30 seconds'; 14 cells is only 19.5 s).
    {obstacles = 2, types = {'pit', 'gap'},           grid = 6, minPath = 21, minTurns = 3, branches = 2, maxPathFrac = 0.7},
    {obstacles = 3, types = {'pit', 'gap', 'ledge'},  grid = 8, minPath = 27, minTurns = 4, branches = 3},
    {obstacles = 4, types = {'pit', 'gap', 'ledge'},  grid = 9, minPath = 33, minTurns = 5, branches = 4},
}

-- Level sequence: the authored tutorial, then one generated level per
-- LEVELGEN_DIFFICULTY row (level i uses row i - 1), then the ending.
BACKROOMS_GENERATED_LEVELS = #LEVELGEN_DIFFICULTY
-- Run seed for the generated levels: nil picks a random one per run (logged
-- as "[backrooms] run seed N"). `love . --run-seed=N` sets it so a run can be
-- replayed; level seeds are LevelGen.levelSeed(run seed, level index).
BACKROOMS_RUN_SEED = nil

-- Seed pickups: collected by walking within this horizontal distance (m).
BACKROOMS_PICKUP_RADIUS = 0.9
BACKROOMS_PICKUP_HEIGHT = 0.5

-- Backrooms look (src/BackroomsLook.lua, shaders/backrooms.glsl) ---------------
-- Purely visual: nothing here touches collision, plots, pickups or layout.
BACKROOMS_LOOK_MAX_LIGHTS = 8          -- nearest fixtures uploaded per frame (matches MAX_LIGHTS in the shader)
BACKROOMS_LOOK_QUALITIES = {'high', 'medium', 'low'}   -- low: no flicker; (shafts/bloom arrive in later sections)
BACKROOMS_LIGHT_COLOR = {1.0, 0.93, 0.70}    -- warm off-white fluorescent
BACKROOMS_LIGHT_RADIUS = 6.0                 -- m, falls to zero at this distance
BACKROOMS_LIGHT_SPACING = 5.5                -- m between auto-placed ceiling fixtures
BACKROOMS_FIXTURE_SIZE = {1.2, 0.6}          -- recessed panel, m
-- Lighting presets: ambient (rgb, the floor of the lighting on room surfaces),
-- fog colour/density (exp), fixture intensity, one fixture in `litEvery` is lit
-- (the rest are dead panels), the mix of the lit ones, and `gameplayFloor`:
-- the minimum light on plots, crops, pickups and the exit, so they stay
-- readable in every preset.
BACKROOMS_LIGHT_PRESETS = {
    ['bright'] = {fixtureColor = {1, 0.97, 0.82}, ambient = {0.62, 0.58, 0.36}, fogColor = {0.56, 0.47, 0.22}, fogDensity = 0.030,
        intensity = 1.6, litEvery = 1, flicker = 0.08, buzz = 0.08, gameplayFloor = 0.7},
    ['dim'] = {fixtureColor = {1, 0.9, 0.66}, ambient = {0.34, 0.31, 0.19}, fogColor = {0.30, 0.24, 0.11}, fogDensity = 0.046,
        intensity = 1.7, litEvery = 1, flicker = 0.30, buzz = 0.15, gameplayFloor = 0.72},
    ['single-bulb'] = {fixtureColor = {1, 0.78, 0.48}, ambient = {0.20, 0.18, 0.10}, fogColor = {0.17, 0.14, 0.07}, fogDensity = 0.055,
        intensity = 2.0, litEvery = 4, flicker = 0.45, buzz = 0.2, gameplayFloor = 0.78},
    ['near-dark'] = {fixtureColor = {0.82, 0.9, 1}, ambient = {0.16, 0.14, 0.08}, fogColor = {0.07, 0.06, 0.03}, fogDensity = 0.075,
        intensity = 1.6, litEvery = 5, flicker = 0.4, buzz = 0.2, gameplayFloor = 0.82},
}
-- default preset for a room with no `lighting`: picked from its id by hash
-- (so the same level always looks the same), except these fixed ones
BACKROOMS_LIGHTING_BY_ROOM_ID = {tutorial = 'bright'}
BACKROOMS_LIGHTING_DEFAULT_POOL = {'bright', 'dim', 'dim', 'single-bulb', 'near-dark'}
BACKROOMS_SHADOW_ALPHA = 0.55          -- peak darkness of a contact-shadow blob

-- Zones / room shapes / audio: shared contracts for backrooms-zones-variety-audio.
-- LevelGen output: data.meta.zones = {{id='z1', theme, lighting, cellCount, adjacent={ids}}, ...};
-- each data.meta.cells[i].zone = zone id. Later groups add zone ids to boxes/fixtures/props/checkpoints.
BACKROOMS_ZONE_LIGHTING_POOL = {'bright', 'dim', 'single-bulb', 'near-dark'}   -- keys of BACKROOMS_LIGHT_PRESETS
BACKROOMS_ZONE_BLEND_DISTANCE = 2.5    -- m over which ambient/fog blend toward the neighbouring zone
-- Shape contract: a shape declares {name, cells (offsets), removeWalls, ceilingBonus}; stays in one region
-- and elevation, excludes module/start/exit cells, uses its own RNG stream. Weights 0 = disabled.
ROOM_SHAPE_NAMES = {'hall', 'room2x2', 'room1x2', 'room2x3', 'roomL', 'pillared', 'atrium', 'gallery', 'closet'}
ROOM_SHAPE_WEIGHTS = {hall = 1, room2x2 = 1, room1x2 = 1, room2x3 = 0.6, roomL = 0.8, pillared = 0.4, atrium = 0.3, gallery = 0.6, closet = 0.5}
ROOM_SHAPE_CHANCE = 0.45               -- per candidate stamp: chance = weight * this
ROOM_SHAPE_MAX = 6                     -- most new-shape rooms per level (2x2 rooms have LEVELGEN_MAX_ROOMS)
ROOM_PILLAR_SIZE = 0.7                 -- m, square pillar
ROOM_CLOSET_INSET = 0.6                -- m of side slab per side in a closet
ROOM_CLOSET_CEIL_DROP = 1              -- m lower ceiling in a closet
ROOM_CLOSET_MAX = 3
ROOM_PILLAR_CLEARANCE = 1.2            -- m between a pillar and walls/other pillars
ROOM_ATRIUM_CEILING_BONUS = 2.5        -- extra ceiling height of a crossroads atrium
-- Audio (src/BackroomsAudio.lua, owned by the audio group)
BACKROOMS_HUM_FILE = 'sounds/BackroomsHum.mp3'     -- streamed, looping
BACKROOMS_FOOTSTEP_FILES = {'sounds/Footsteps Rug 1.wav', 'sounds/Footsteps Rug 2.wav', 'sounds/Footsteps Rug 3.wav',
    'sounds/Footsteps Rug 4.wav', 'sounds/Footsteps Rug 5.wav'}   -- verify names against sounds/
BACKROOMS_FOOTSTEP_STRIDE = 1.7        -- m of ground travel per step
BACKROOMS_FOOTSTEP_PITCH_VARIATION = 0.06
BACKROOMS_FOOTSTEP_VOLUME_VARIATION = 0.10
BACKROOMS_HUM_VOLUME = 0.25
BACKROOMS_FOOTSTEP_VOLUME = 0.7
BACKROOMS_HUM_FADE = 1.0               -- s
