-- 2D farm rules, kept separate from FarmState's input/rendering so they can be
-- tested headlessly. Plots must be tilled before they take a seed; growth is
-- advanced by elapsed time (Farm.advance, called from FarmState:update), at
-- the full rate when watered and FARM_UNWATERED_RATE otherwise. Inventory
-- lives in the shared game-data table (seeds, crops, coins, hasSold).

Farm = {}

-- Plot states
PLOT_EMPTY = 'empty'
PLOT_GROWING = 'growing'
PLOT_MATURE = 'mature'

function Farm.newPlot(col, row)
    -- progress: full-rate growth seconds since planting
    return {col = col, row = row, state = PLOT_EMPTY, seedType = nil, stage = 0, progress = 0,
        tilled = false, watered = false}
end

-- Builds the plot grid from the FARM_PLOTS rectangle.
function Farm.newPlots()
    local plots = {}
    for row = FARM_PLOTS.row, FARM_PLOTS.row + FARM_PLOTS.rows - 1 do
        for col = FARM_PLOTS.col, FARM_PLOTS.col + FARM_PLOTS.cols - 1 do
            plots[#plots + 1] = Farm.newPlot(col, row)
        end
    end
    return plots
end

function Farm.totalSeeds(gameData)
    local n = 0
    for _, seedType in ipairs(SEED_TYPES) do n = n + (gameData.seeds[seedType] or 0) end
    return n
end

function Farm.totalCrops(gameData)
    local n = 0
    for _, seedType in ipairs(SEED_TYPES) do n = n + (gameData.crops[seedType] or 0) end
    return n
end

-- The seed type a plant action would use: the preferred type if any are left,
-- otherwise the first type in SEED_TYPES order that still has seeds, or nil.
function Farm.pickSeed(gameData, preferred)
    if preferred and (gameData.seeds[preferred] or 0) > 0 then return preferred end
    for _, seedType in ipairs(SEED_TYPES) do
        if (gameData.seeds[seedType] or 0) > 0 then return seedType end
    end
    return nil
end

-- Tills an empty, untilled plot. Returns ok, reason ('occupied' | 'tilled').
function Farm.till(plot)
    if plot.state ~= PLOT_EMPTY then return false, 'occupied' end
    if plot.tilled then return false, 'tilled' end
    plot.tilled = true
    return true
end

-- Waters a growing, unwatered plot (once per crop; no refill needed).
-- Returns ok, reason ('not-growing' | 'watered').
function Farm.water(plot)
    if plot.state ~= PLOT_GROWING then return false, 'not-growing' end
    if plot.watered then return false, 'watered' end
    plot.watered = true
    return true
end

-- Plants on an empty tilled plot, consuming one seed. Growth then advances
-- through Farm.advance. Returns ok, seedTypeOrReason ('occupied' |
-- 'untilled' | 'no-seeds').
function Farm.plant(plot, gameData, preferred)
    if plot.state ~= PLOT_EMPTY then return false, 'occupied' end
    if not plot.tilled then return false, 'untilled' end
    local seedType = Farm.pickSeed(gameData, preferred)
    if not seedType then return false, 'no-seeds' end

    gameData.seeds[seedType] = gameData.seeds[seedType] - 1
    plot.state = PLOT_GROWING
    plot.seedType = seedType
    plot.stage = 1
    plot.progress = 0
    plot.watered = false
    return true, seedType
end

-- Current growth rate of a plot (full-rate seconds per second).
function Farm.growthRate(plot)
    return plot.watered and 1 or FARM_UNWATERED_RATE
end

-- Seconds of real time a freshly planted crop needs to mature.
function Farm.growthTime(watered)
    return FARM_STAGE_TIME * (FARM_GROWTH_STAGES - 1) / (watered and 1 or FARM_UNWATERED_RATE)
end

-- Advances a growing plot by `dt` seconds. Returns the new stage when the
-- stage changed this call (FARM_GROWTH_STAGES means it just matured), else nil.
function Farm.advance(plot, dt)
    if plot.state ~= PLOT_GROWING then return nil end
    plot.progress = plot.progress + dt * Farm.growthRate(plot)
    -- the tiny epsilon keeps accumulated 1/60 s steps from landing a hair
    -- short of an exact stage boundary
    local stage = math.min(FARM_GROWTH_STAGES, 1 + math.floor(plot.progress / FARM_STAGE_TIME + 1e-9))
    if stage == plot.stage then return nil end
    plot.stage = stage
    if stage >= FARM_GROWTH_STAGES then plot.state = PLOT_MATURE end
    return stage
end

-- Harvests a mature crop into gameData.crops and clears the plot. The plot
-- stays tilled; the water is used up. Returns ok, seedTypeOrReason ('empty'
-- | 'immature').
function Farm.harvest(plot, gameData)
    if plot.state == PLOT_EMPTY then return false, 'empty' end
    if plot.state ~= PLOT_MATURE then return false, 'immature' end

    local seedType = plot.seedType
    gameData.crops[seedType] = (gameData.crops[seedType] or 0) + 1
    plot.state = PLOT_EMPTY
    plot.seedType = nil
    plot.stage = 0
    plot.progress = 0
    plot.watered = false
    return true, seedType
end

-- The crop type a sale would use (same preference rule as pickSeed), or nil.
function Farm.pickCrop(gameData, preferred)
    if preferred and (gameData.crops[preferred] or 0) > 0 then return preferred end
    for _, seedType in ipairs(SEED_TYPES) do
        if (gameData.crops[seedType] or 0) > 0 then return seedType end
    end
    return nil
end

-- Sells one harvested crop to a villager for coins and marks hasSold.
-- Returns ok, seedType, value -- or false, 'no-crops' with nothing changed.
-- (Over-selling with zero crops is the break trigger; see Farm.isOverSell.)
function Farm.sell(gameData, preferred)
    local seedType = Farm.pickCrop(gameData, preferred)
    if not seedType then return false, 'no-crops' end

    local value = CROP_VALUES[seedType] or 1
    gameData.crops[seedType] = gameData.crops[seedType] - 1
    gameData.coins = gameData.coins + value
    gameData.hasSold = true
    return true, seedType, value
end

-- Buys one `seedType` seed for SEED_PRICES[seedType] coins. Only coins and
-- that seed count change (crops, hasSold and the break are untouched).
-- Returns ok, seedType, price -- or false, reason ('unknown-seed' |
-- 'no-coins'), price with nothing changed.
function Farm.buySeed(gameData, seedType)
    local price = SEED_PRICES[seedType]
    if not price then return false, 'unknown-seed' end
    if (gameData.coins or 0) < price then return false, 'no-coins', price end
    gameData.coins = gameData.coins - price
    gameData.seeds[seedType] = (gameData.seeds[seedType] or 0) + 1
    return true, seedType, price
end

-- True when a sale attempt right now would be an over-sell: the player has
-- completed at least one sale and has no crops left. FarmState starts the
-- break on this; before the first sale an empty-handed attempt is harmless.
function Farm.isOverSell(gameData)
    return gameData.hasSold == true and Farm.totalCrops(gameData) == 0
end
