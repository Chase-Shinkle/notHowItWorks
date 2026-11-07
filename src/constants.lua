-- Window and virtual dimensions
WINDOW_WIDTH = 800
WINDOW_HEIGHT = 800

VIRTUAL_WIDTH = 320
VIRTUAL_HEIGHT = 320

-- Debug helpers: when enabled, DEBUG_ADVANCE_KEY jumps to the next state
-- (start -> farm -> backrooms -> start) so the flow can be checked without
-- playing through it.
DEBUG_MODE = true
DEBUG_ADVANCE_KEY = 'f1'

-- Seed types shared by the farm and the backrooms, in display order.
SEED_TYPES = {'beanstalk', 'pumpkin', 'vine'}

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
-- plants.
FARM_PLAYER_START = {col = 3, row = 6, facing = 'up'}

-- Growth: a crop moves through FARM_GROWTH_STAGES visible stages (1 = seeds,
-- last = mature), one stage every FARM_STAGE_TIME seconds (12 s in total).
FARM_GROWTH_STAGES = 5
FARM_STAGE_TIME = 3

-- Coins paid by villagers per harvested crop.
CROP_VALUES = {
    beanstalk = 3,
    pumpkin = 5,
    vine = 4,
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
-- Room 1 (tutorial) is finished with a single beanstalk seed; keep this in
-- sync with Room 1's data when it is built (task 5.4).
FIRST_ROOM_MIN_SEEDS = {
    beanstalk = 1,
}
