-- Shared game-data table passed between top-level states through
-- gStateMachine:change(name, gameData). The backrooms only reads `seeds`.

function NewGameData(overrides)
    overrides = overrides or {}

    local seeds = {}
    for _, seedType in ipairs(SEED_TYPES) do
        local source = overrides.seeds or STARTING_SEEDS
        seeds[seedType] = source[seedType] or 0
    end

    -- harvested crops are counted per seed type, like seeds
    local crops = {}
    for _, seedType in ipairs(SEED_TYPES) do
        crops[seedType] = (overrides.crops or {})[seedType] or 0
    end

    return {
        seeds = seeds,
        coins = overrides.coins or 0,
        crops = crops,
        hasSold = overrides.hasSold or false,
        hasBroken = overrides.hasBroken or false,   -- the farm break has started
    }
end

-- The game data the backrooms receives after the break: seeds only (coins and
-- crops are dropped), each seed type topped up to at least `minimums[type]`
-- (default FIRST_ROOM_MIN_SEEDS). Returns a new table; `gameData` is unchanged.
function CarryOverGameData(gameData, minimums)
    minimums = minimums or FIRST_ROOM_MIN_SEEDS
    local seeds = {}
    for _, seedType in ipairs(SEED_TYPES) do
        seeds[seedType] = math.max((gameData.seeds or {})[seedType] or 0, minimums[seedType] or 0)
    end
    return NewGameData({
        seeds = seeds,
        hasSold = gameData.hasSold,
        hasBroken = gameData.hasBroken,
    })
end

-- Stable, human-readable seed summary, e.g. "beanstalk=2 pumpkin=2 vine=2".
function FormatSeeds(seeds)
    local parts = {}
    for _, seedType in ipairs(SEED_TYPES) do
        parts[#parts + 1] = seedType .. '=' .. tostring((seeds or {})[seedType] or 0)
    end
    return table.concat(parts, ' ')
end

-- A fresh {type = n} table with every seed type (missing types become 0).
function CopySeeds(seeds)
    local copy = {}
    for _, seedType in ipairs(SEED_TYPES) do
        copy[seedType] = (seeds or {})[seedType] or 0
    end
    return copy
end

-- Seeds the player holds when entering backrooms room number `index`
-- (`roomData` is that room's data table). Returns a new table.
--
-- Policy (an explicit, documented exception to the room-puzzles wording
-- "their seeds equal that room's allotment"; see design.md decision 9):
--   * Room 1, first entry: the seeds carried over from the farm are kept and
--     each type is topped up to Room 1's allotment, which acts as the minimum
--     (seed-carryover: "holds the seeds they had at the break").
--   * Rooms 2+: seeds are exactly that room's fixed allotment. Leftovers from
--     the previous room do not carry forward.
-- Resetting a room restores the seeds recorded when it was entered (for
-- Room 1 that is the topped-up farm seeds, not the bare allotment).
function RoomStartingSeeds(roomData, index, carriedSeeds)
    local allotment = (roomData and roomData.allotment) or {}
    if index == 1 then
        local seeds = CopySeeds(carriedSeeds)
        for _, seedType in ipairs(SEED_TYPES) do
            seeds[seedType] = math.max(seeds[seedType], allotment[seedType] or 0)
        end
        return seeds
    end
    return CopySeeds(allotment)
end
