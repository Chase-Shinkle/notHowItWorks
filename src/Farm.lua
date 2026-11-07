-- 2D farm rules, kept separate from FarmState's input/rendering so they can be
-- tested headlessly. Plots grow through knife Timer callbacks; inventory lives
-- in the shared game-data table (seeds, crops, coins, hasSold).

Farm = {}

-- Plot states
PLOT_EMPTY = 'empty'
PLOT_GROWING = 'growing'
PLOT_MATURE = 'mature'

function Farm.newPlot(col, row)
    return {col = col, row = row, state = PLOT_EMPTY, seedType = nil, stage = 0, timer = nil}
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

-- Plants on an empty plot, consuming one seed, and starts timed growth.
-- `timerGroup` (optional) is the knife Timer group that drives growth.
-- Returns ok, seedTypeOrReason ('occupied' | 'no-seeds').
function Farm.plant(plot, gameData, preferred, timerGroup)
    if plot.state ~= PLOT_EMPTY then return false, 'occupied' end
    local seedType = Farm.pickSeed(gameData, preferred)
    if not seedType then return false, 'no-seeds' end

    gameData.seeds[seedType] = gameData.seeds[seedType] - 1
    plot.state = PLOT_GROWING
    plot.seedType = seedType
    plot.stage = 1

    -- one stage per interval; the last stage is mature
    plot.timer = Timer.every(FARM_STAGE_TIME, function()
        plot.stage = plot.stage + 1
        if plot.stage >= FARM_GROWTH_STAGES then
            plot.stage = FARM_GROWTH_STAGES
            plot.state = PLOT_MATURE
            plot.timer = nil
            return false   -- stops (and removes) this timer
        end
    end)
    if timerGroup then plot.timer:group(timerGroup) end

    return true, seedType
end

-- Harvests a mature crop into gameData.crops and clears the plot.
-- Returns ok, seedTypeOrReason ('empty' | 'immature').
function Farm.harvest(plot, gameData)
    if plot.state == PLOT_EMPTY then return false, 'empty' end
    if plot.state ~= PLOT_MATURE then return false, 'immature' end

    local seedType = plot.seedType
    gameData.crops[seedType] = (gameData.crops[seedType] or 0) + 1
    plot.state = PLOT_EMPTY
    plot.seedType = nil
    plot.stage = 0
    plot.timer = nil
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

-- True when a sale attempt right now would be an over-sell: the player has
-- completed at least one sale and has no crops left. FarmState starts the
-- break on this; before the first sale an empty-handed attempt is harmless.
function Farm.isOverSell(gameData)
    return gameData.hasSold == true and Farm.totalCrops(gameData) == 0
end
