-- Backrooms room data, in play order. Room(data) builds each one (src/Room.lua).
--
-- Every exit starts out of reach: the player has no jump and cannot step up
-- ledges (src/PlayerController.lua), so the only ways up or across are grown
-- crops (src/Crop.lua):
--   beanstalk  climb volume 0.8 x 0.8, 3.0 m tall. Climbing only starts from
--              standing, so it lifts the player up to 3.0 m from where it is
--              planted, but cannot catch a falling player.
--   pumpkin    solid 2.6 x 2.6 x 1.0. With no step-up, its top is only
--              walkable when it grows in a 1.0 m deep pit, where it fills the
--              pit level with the floor.
--   vine       solid 6.0 long x 1.2 wide x 0.3 thick, top level with its
--              plot, growing in the plot's `dir`: a bridge over a gap.
--
-- Room puzzles (see design.md, "Section 5 room geometry", for the reasoning
-- and the measured margins):
--   Room 1  tutorial. One plot holding a half-grown beanstalk at the foot of
--           a 2.6 m ledge; the exit is on the ledge. The demo plot only takes
--           a beanstalk seed; one seed finishes it.
--   Room 2  pumpkin + vine. A 2.6 m wide pit (pumpkin) then a 4 m gap (vine).
--   Room 3  beanstalk + pumpkin + vine. A pit (pumpkin), a 2.6 m ledge
--           (beanstalk), then a 4 m gap at ledge height (vine).
--
-- Pits and gaps are voids: falling below the room's killZ (-0.5) respawns
-- the player at the spawn, keeping the room's crops and seeds, so a fall is
-- never a soft-lock. Pit plots sit on decorative (non-solid) soil columns.
--
-- Seed allotments follow RoomStartingSeeds (src/GameData.lua): Room 1's
-- allotment is the minimum the farm seeds are topped up to and must equal
-- FIRST_ROOM_MIN_SEEDS; Rooms 2 and 3 hand out exactly their allotment (one
-- spare of each type they need, none of the types they do not).

local T = 0.2          -- wall / slab thickness
local VOID_Z = -4      -- bottom of pits and gaps (far below killZ)
local KILL_Z = -0.5

-- Walls on the four sides of the interior [x0, x1] x [y0, y1], from VOID_Z to
-- `height`, and a ceiling at `height`. Floors are listed per room.
local function shell(x0, x1, y0, y1, height)
    local w, d = x1 - x0, y1 - y0
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local zc, zh = (VOID_Z + height) / 2, height - VOID_Z
    return {
        {kind = 'ceiling', pos = {cx, cy, height + T / 2}, size = {w + 2 * T, d + 2 * T, T}},
        {kind = 'wall', pos = {x1 + T / 2, cy, zc}, size = {T, d + 2 * T, zh}},
        {kind = 'wall', pos = {x0 - T / 2, cy, zc}, size = {T, d + 2 * T, zh}},
        {kind = 'wall', pos = {cx, y1 + T / 2, zc}, size = {w, T, zh}},
        {kind = 'wall', pos = {cx, y0 - T / 2, zc}, size = {w, T, zh}},
        -- the bottom of the void (respawn happens first; this only stops the
        -- view from showing nothing)
        {kind = 'floor', pos = {cx, cy, VOID_Z - T / 2}, size = {w, d, T}},
    }
end

-- Floor slab with its top at `top`, spanning x in [x0, x1] and the full room
-- depth [y0, y1].
local function floor(x0, x1, y0, y1, top)
    return {kind = 'floor', pos = {(x0 + x1) / 2, (y0 + y1) / 2, top - T / 2}, size = {x1 - x0, y1 - y0, T}}
end

-- Solid block from VOID_Z up to `top` over x in [x0, x1], full depth.
local function block(x0, x1, y0, y1, top)
    return {kind = 'solid', pos = {(x0 + x1) / 2, (y0 + y1) / 2, (VOID_Z + top) / 2},
        size = {x1 - x0, y1 - y0, top - VOID_Z}}
end

-- Decorative soil column under a pit plot whose surface is at `top`.
local function soilColumn(x, y, top)
    return {kind = 'solid', pos = {x, y, (VOID_Z + top) / 2}, size = {1.2, 1.2, top - VOID_Z},
        color = {0.36, 0.25, 0.16, 1}, collide = false}
end

local EXIT_SIZE = {0.6, 1.4, 2.2}
local function exitAt(x, y, floorTop)
    return {pos = {x, y, floorTop + EXIT_SIZE[3] / 2}, size = EXIT_SIZE}
end

BACKROOMS_ROOMS = {
    -- 1: tutorial. Interior x [-6, 6], y [-3, 3]. Ledge x [2, 6], top 2.6.
    -- Demo beanstalk plot 0.8 m in front of the ledge face, half grown (1.5 m).
    {
        id = 'tutorial',
        name = 'Room 1: something is growing',
        spawn = {-4.5, 0, 0, 0},                     -- facing +x: demo crop and exit ahead
        killZ = KILL_Z,
        boxes = Room.joinBoxes(shell(-6, 6, -3, 3, 6), {
            floor(-6, 2, -3, 3, 0),
            block(2, 6, -3, 3, 2.6),
        }),
        exit = exitAt(5.7, 0, 2.6),
        plots = {
            {id = 'demo', pos = {1.2, 0, 0}},
        },
        demoCrops = {
            {plot = 'demo', seed = 'beanstalk', progress = 0.5},
        },
        allotment = CopySeeds(FIRST_ROOM_MIN_SEEDS),
        billboards = {
            -- kept small and against the side walls so nothing fills the view
            -- near the spawn
            {texture = 'crop-beanstalk-4', pos = {0.2, -2.6, 0}, height = 0.7},
            {texture = 'seedbag-beanstalk', pos = {-1, 2.6, 0}, height = 0.5},
            {texture = 'well', pos = {1.0, 2.4, 0}, height = 1.0},
            {texture = 'villager', pos = {-5.2, 2.2, 0}, height = 1.6},
        },
    },

    -- 2: pumpkin + vine. Interior x [-8, 10], y [-3, 3].
    --   A  floor x [-8, -4]      spawn
    --   pit x [-4, -1.4], 1.0 m deep plot 'pit' at its centre (pumpkin)
    --   B  floor x [-1.4, 2]     plot 'edge' 0.8 m before the gap, vine +x
    --   gap x [2, 6]
    --   C  floor x [6, 10]       exit
    {
        id = 'pit-and-gap',
        name = 'Room 2: fill it, then cross it',
        spawn = {-7, 0, 0, 0},
        killZ = KILL_Z,
        boxes = Room.joinBoxes(shell(-8, 10, -3, 3, 3.5), {
            floor(-8, -4, -3, 3, 0),
            floor(-1.4, 2, -3, 3, 0),
            floor(6, 10, -3, 3, 0),
            soilColumn(-2.7, 0, -1.0),
        }),
        exit = exitAt(9.7, 0, 0),
        plots = {
            {id = 'pit', pos = {-2.7, 0, -1.0}, dir = '+x'},
            {id = 'edge', pos = {1.2, 0, 0}, dir = '+x'},
        },
        allotment = {pumpkin = 2, vine = 2},
        billboards = {
            {texture = 'crop-pumpkin-5', pos = {-7.4, 2.4, 0}, height = 1},
            {texture = 'produce-vine', pos = {-0.6, -2.4, 0}, height = 0.6},
            {texture = 'hero', pos = {8.5, 2.4, 0}, height = 1.5},
            {texture = 'bucket', pos = {-5.5, -2.6, 0}, height = 0.5},
        },
    },

    -- 3: beanstalk + pumpkin + vine (final room). Interior x [-9, 10], y [-3, 3].
    --   A  floor x [-9, -6]      spawn
    --   pit x [-6, -3.4], plot 'pit' (pumpkin)
    --   B  floor x [-3.4, -1]    plot 'foot' 0.8 m before the ledge face
    --                            (beanstalk); a vine here grows along +y
    --   H  ledge x [-1, 2], top 2.6, plot 'lip' 0.8 m before the gap, vine +x
    --   gap x [2, 6] at ledge height, open down to the void
    --   C  ledge x [6, 10], top 2.6, exit
    {
        id = 'pit-ledge-gap',
        name = 'Room 3: all of it',
        spawn = {-8, 0, 0, 0},
        killZ = KILL_Z,
        boxes = Room.joinBoxes(shell(-9, 10, -3, 3, 6), {
            floor(-9, -6, -3, 3, 0),
            floor(-3.4, -1, -3, 3, 0),
            block(-1, 2, -3, 3, 2.6),
            block(6, 10, -3, 3, 2.6),
            soilColumn(-4.7, 0, -1.0),
        }),
        exit = exitAt(9.7, 0, 2.6),
        plots = {
            {id = 'pit', pos = {-4.7, 0, -1.0}, dir = '+x'},
            {id = 'foot', pos = {-1.8, 0, 0}, dir = '+y'},
            {id = 'lip', pos = {1.2, 0, 2.6}, dir = '+x'},
        },
        allotment = {beanstalk = 2, pumpkin = 2, vine = 2},
        billboards = {
            {texture = 'crop-vine-5', pos = {-8.4, -2.4, 0}, height = 1.1},
            {texture = 'seedbag-pumpkin', pos = {-2.2, 2.4, 0}, height = 0.6},
            {texture = 'sacks', pos = {-8.5, 2.5, 0}, height = 0.6},
            {texture = 'villager', pos = {8.8, -2.2, 2.6}, height = 1.6},
        },
    },
}
