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
