-- Backrooms room data, in play order. Room(data) builds each one (src/Room.lua).
--
-- SECTION 4 FIXTURES: these three rooms only exercise the world systems
-- (movement, collision, gravity, billboards, exits, progression, ending).
-- Their exits are reachable on foot, so they do NOT yet satisfy the
-- room-progression "exit cannot be reached without growing crop structures"
-- requirement or any puzzle requirement. They are replaced by the real
-- puzzle rooms in tasks 5.4 (Room 1 tutorial), 5.6 (Room 2) and 5.7 (Room 3).
--
-- Seed allotments follow the policy in RoomStartingSeeds (src/GameData.lua):
-- Room 1's allotment is the minimum the farm seeds are topped up to (and must
-- equal FIRST_ROOM_MIN_SEEDS, which the farm break uses); later rooms hand out
-- exactly their allotment.

local H = 3   -- ceiling height

BACKROOMS_ROOMS = {
    -- 1: plain box room with farm sprites; walk to the glowing doorway.
    {
        id = 'fixture-box',
        name = 'Room 1 (fixture: plain box room)',
        spawn = {-3.5, 0, 0, 0},                       -- facing +x, towards the exit
        boxes = Room.shellBoxes(10, 10, H),
        exit = {pos = {4.6, 0, 1.1}, size = {0.6, 1.4, 2.2}},
        plots = {
            {id = 'a', pos = {0, -2, 0}},
            {id = 'b', pos = {0, 2, 0}},
        },
        allotment = CopySeeds(FIRST_ROOM_MIN_SEEDS),
        billboards = {
            {texture = 'crop-pumpkin-5', pos = {1.5, 3, 0}, height = 1},
            {texture = 'crop-beanstalk-4', pos = {-1, -3.2, 0}, height = 1.2},
            {texture = 'villager', pos = {2.5, -2.5, 0}, height = 1.6},
            {texture = 'produce-vine', pos = {-3, 3, 0}, height = 0.6},
        },
    },

    -- 2: spawn on a raised ledge (step off and fall to the floor), a pillar
    -- in the middle to slide around, exit on the far wall.
    {
        id = 'fixture-ledge',
        name = 'Room 2 (fixture: ledge and pillar)',
        spawn = {-4, 0, 1, 0},
        boxes = Room.joinBoxes(Room.shellBoxes(12, 8, H), {
            {kind = 'solid', pos = {-4.5, 0, 0.5}, size = {3, 8, 1}},   -- ledge, top at z = 1
            {kind = 'solid', pos = {1, 0, H / 2}, size = {1, 1, H}},    -- pillar
        }),
        exit = {pos = {5.6, 0, 1.1}, size = {0.6, 1.4, 2.2}},
        plots = {{id = 'a', pos = {2.5, 2, 0}}},
        allotment = {beanstalk = 1, pumpkin = 1},
        billboards = {
            {texture = 'crop-vine-5', pos = {3, -2.5, 0}, height = 1.1},
            {texture = 'hero', pos = {-1.5, 2.8, 0}, height = 1.5},
        },
    },

    -- 3: L-shaped corridor (final room): the exit is round the corner.
    {
        id = 'fixture-corridor',
        name = 'Room 3 (fixture: corridor)',
        spawn = {-5, -3, 0, 0},
        boxes = Room.joinBoxes(Room.shellBoxes(12, 8, H), {
            {kind = 'wall', pos = {-1, 1, H / 2}, size = {10, 0.4, H}},   -- divider, gap at +x
        }),
        exit = {pos = {-5.6, 2.5, 1.1}, size = {0.6, 1.4, 2.2}},
        plots = {{id = 'a', pos = {3, -2, 0}}},
        allotment = {beanstalk = 1, pumpkin = 1, vine = 1},
        billboards = {
            {texture = 'crop-pumpkin-3', pos = {5, -3, 0}, height = 0.8},
            {texture = 'seedbag-beanstalk', pos = {4.5, 2.5, 0}, height = 0.6},
        },
    },
}
