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
