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
    }
end

-- Stable, human-readable seed summary, e.g. "beanstalk=2 pumpkin=2 vine=2".
function FormatSeeds(seeds)
    local parts = {}
    for _, seedType in ipairs(SEED_TYPES) do
        parts[#parts + 1] = seedType .. '=' .. tostring((seeds or {})[seedType] or 0)
    end
    return table.concat(parts, ' ')
end
