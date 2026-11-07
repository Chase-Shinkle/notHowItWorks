-- 2D farm. Renders through push at the 320x320 virtual resolution.
--
-- Controls (keyboard): WASD/arrows move the farmer one tile per press (hold
-- to repeat); E/Space/Enter uses the tile the farmer faces: on a plot it
-- tills, plants, waters or harvests depending on the plot (plotAction); on the
-- villager it sells, at the seed stall it buys; 1-3 pick a seed type, Tab/Q
-- cycles it.
-- Controls (mouse): hover highlights a plot, the villager or the seed stall,
-- left click uses it directly; clicking a seed slot in the top bar selects
-- that seed.
--
-- Rules live in src/Farm.lua; growth is advanced by elapsed time in
-- FarmState:update (never during the break). `self.timers` is a knife Timer
-- group owned by this state for anything farm-local; it is cleared on exit.
--
-- The break: after the first sale the villager keeps asking for crops. Trying
-- to sell with none left (an over-sell), or FARM_IDLE_BREAK_TIME seconds after
-- the last sale without one, starts a one-shot glitch sequence (shake,
-- corruption, fall) on its own Timer group. Input is ignored while it plays;
-- when it ends the farm changes to the backrooms with seeds only
-- (CarryOverGameData).
FarmState = Class{__includes = BaseState}

FarmState.usesPush = true

local DIRS = {
    up = {0, -1},
    down = {0, 1},
    left = {-1, 0},
    right = {1, 0},
}
local DIR_ORDER = {'up', 'down', 'left', 'right'}


local function anyPressed(keys)
    for _, key in ipairs(keys) do
        if love.keyboard.wasPressed(key) then return true end
    end
    return false
end

local function anyDown(keys)
    if not love.keyboard.isDown then return false end
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then return true end
    end
    return false
end

-- top-left pixel of a tile
function FarmTileToPixel(col, row)
    return (col - 1) * FARM_TILE, (row - 1) * FARM_TILE
end

-- tile under a virtual-resolution pixel, or nil outside the screen
function FarmPixelToTile(x, y)
    if not x or not y or x < 0 or y < 0 or x >= VIRTUAL_WIDTH or y >= VIRTUAL_HEIGHT then
        return nil
    end
    return math.floor(x / FARM_TILE) + 1, math.floor(y / FARM_TILE) + 1
end

function FarmState:enter(gameData)
    self.gameData = gameData or NewGameData()
    self.timers = {}                      -- knife Timer group for crop growth
    self.plots = Farm.newPlots()
    self:buildDecor()

    self.player = {
        col = FARM_PLAYER_START.col,
        row = FARM_PLAYER_START.row,
        facing = FARM_PLAYER_START.facing,
    }
    self.player.drawX, self.player.drawY = FarmTileToPixel(self.player.col, self.player.row)
    self.heldDir = nil
    self.repeatTimer = 0

    self.selectedSeed = Farm.pickSeed(self.gameData, SEED_TYPES[1]) or SEED_TYPES[1]
    self.hover = nil                      -- {col, row} under the mouse
    -- game-feel effects (src/Fx.lua); popups is its floating-text list
    self.juice = Fx.new()
    self.popups = self.juice.popups
    self.displayCoins = self.gameData.coins or 0   -- the HUD's ticking coin count
    self.coinTickTimer = 0
    self.time = 0                         -- seconds on the farm outside the break (ambient motion)
    self.dayTime = FARM_DAY_START_PHASE * FARM_DAY_LENGTH   -- day cycle clock, paused in the break
    self.villagerLine = nil               -- {text, time left}

    -- the break
    self.idleTimer = 0                    -- seconds since the last sale
    self.nagTimer = 0                     -- seconds until the next request
    self.nagIndex = 0
    self.breakTimers = {}                 -- knife Timer group for the sequence
    self.breaking = false                 -- sequence playing; input locked
    self.breakReason = nil                -- 'oversell' | 'idle'
    self.breakDone = false                -- set by the last sequence timer
    self.transitioned = false             -- the change to backrooms happened
    self.fx = {shake = 0, corruption = 0, fall = 0}

    local music = gSounds['farm-music']
    if music then music:setLooping(true); music:play() end
end

function FarmState:exit()
    Timer.clear(self.timers)
    Timer.clear(self.breakTimers)
    local music = gSounds['farm-music']
    if music then music:stop() end
end

-- World queries ----------------------------------------------------------------

function FarmState:plotAt(col, row)
    for _, plot in ipairs(self.plots) do
        if plot.col == col and plot.row == row then return plot end
    end
    return nil
end

function FarmState:isVillagerAt(col, row)
    return col == FARM_VILLAGER.col and row == FARM_VILLAGER.row
end

function FarmState:isShopAt(col, row)
    return col == FARM_SHOP.col and row == FARM_SHOP.row
end

-- What the player can use at a tile: {kind = 'plot', plot} or
-- {kind = 'villager'} or {kind = 'shop'} or nil.
function FarmState:targetAt(col, row)
    if not col then return nil end
    local plot = self:plotAt(col, row)
    if plot then return {kind = 'plot', plot = plot, col = col, row = row} end
    if self:isVillagerAt(col, row) then return {kind = 'villager', col = col, row = row} end
    if self:isShopAt(col, row) then return {kind = 'shop', col = col, row = row} end
    return nil
end

-- Builds the dressing from FARM_DECOR: `blocked` (solid tiles), `pathTiles`
-- and the ground variation (tufts and stones on free grass tiles), from a
-- fixed-seed local generator so the layout is the same on every entry and the
-- global math.random sequence (used by the break's corruption) is untouched.
function FarmState:buildDecor()
    local D = FARM_DECOR
    local function key(c, r) return c .. ',' .. r end
    self.blocked, self.pathTiles = {}, {}
    for _, list in ipairs({D.fence, D.well, D.bushes, D.pond, D.barn.blocks}) do
        for _, t in ipairs(list) do self.blocked[key(t[1], t[2])] = true end
    end
    for _, t in ipairs(D.path) do self.pathTiles[key(t[1], t[2])] = true end

    local seed = D.groundSeed
    local function rand()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    self.groundDecor = {}
    for row = FARM_FIELD_TOP, FARM_FIELD_BOTTOM do
        for col = 1, FARM_COLS do
            local k = key(col, row)
            local free = not self.blocked[k] and not self.pathTiles[k] and not self:targetAt(col, row)
                and not (col == FARM_PLAYER_START.col and row == FARM_PLAYER_START.row)
            local r1, r2, r3, r4 = rand(), rand(), rand(), rand()
            if free and r1 < D.tuftChance then
                self.groundDecor[#self.groundDecor + 1] = {kind = 'tuft', col = col, row = row,
                    x = math.floor(4 + r2 * 22), y = math.floor(8 + r3 * 18), phase = r4 * 6.28}
            elseif free and r1 < D.tuftChance + D.stoneChance then
                self.groundDecor[#self.groundDecor + 1] = {kind = 'stone', col = col, row = row,
                    x = math.floor(4 + r2 * 22), y = math.floor(6 + r3 * 20), big = r4 < 0.4}
            end
        end
    end
end

function FarmState:isBlockedDecor(col, row)
    return self.blocked[col .. ',' .. row] == true
end

function FarmState:isWalkable(col, row)
    if col < 1 or col > FARM_COLS or row < FARM_FIELD_TOP or row > FARM_FIELD_BOTTOM then
        return false
    end
    if self:isBlockedDecor(col, row) then return false end
    return self:targetAt(col, row) == nil
end

function FarmState:facingTile()
    local d = DIRS[self.player.facing]
    return self.player.col + d[1], self.player.row + d[2]
end

-- The thing the farmer faces (keyboard target).
function FarmState:facingTarget()
    return self:targetAt(self:facingTile())
end

-- Actions ----------------------------------------------------------------------

-- Turn to face `dir`, then step if the tile ahead is free. Returns true if
-- the farmer moved.
function FarmState:tryMove(dir)
    self.player.facing = dir
    local col, row = self:facingTile()
    if self:isWalkable(col, row) then
        self.player.col, self.player.row = col, row
        return true
    end
    return false
end

function FarmState:selectSeed(seedType)
    self.selectedSeed = seedType
end

function FarmState:cycleSeed()
    for i, seedType in ipairs(SEED_TYPES) do
        if seedType == self.selectedSeed then
            self.selectedSeed = SEED_TYPES[i % #SEED_TYPES + 1]
            return
        end
    end
    self.selectedSeed = SEED_TYPES[1]
end

function FarmState:popup(text, col, row, color)
    local x, y = FarmTileToPixel(col, row)
    self.juice:popup(text, x + FARM_TILE / 2, y, color)
end

-- Emits the `kind` burst on a tile and pops what is drawn there. Nothing is
-- emitted while the break plays. Returns true if something was emitted.
function FarmState:emit(kind, col, row)
    if self.breaking then return false end
    local x, y = FarmTileToPixel(col, row)
    self.juice:burst(kind, x + FARM_TILE / 2, y + FARM_TILE * 0.6)
    self.juice:pop(col .. ',' .. row)
    return true
end

-- Centre of a seed type's produce slot in the top bar (virtual px).
function FarmState:produceSlotCenter(seedType)
    for i, t in ipairs(SEED_TYPES) do
        if t == seedType then
            local r = self:hudLayout().produce[i].icon
            return r.x + r.size / 2, r.y + r.size / 2
        end
    end
    return VIRTUAL_WIDTH / 2, FARM_TILE / 2
end

-- Centre of the coin icon in the top bar (virtual px).
function FarmState:coinIconCenter()
    local r = self:hudLayout().coinIcon
    return r.x + r.w / 2, r.y + r.h / 2
end

function FarmState:say(text, duration)
    self.villagerLine = {text = text, time = duration or 2.5}
end

-- What using `plot` would do right now; the single source for the action, the
-- hint text and the tool icon: 'till' | 'plant' | 'no-seeds' | 'water' |
-- 'growing' | 'harvest'.
function FarmState:plotAction(plot)
    if plot.state == PLOT_EMPTY then
        if not plot.tilled then return 'till' end
        return Farm.pickSeed(self.gameData, self.selectedSeed) and 'plant' or 'no-seeds'
    elseif plot.state == PLOT_MATURE then
        return 'harvest'
    end
    return plot.watered and 'growing' or 'water'
end

-- Texture key of the tool shown beside the farmer for the faced plot (from
-- plotAction), or nil when nothing usable is faced.
function FarmState:toolIcon()
    local target = self:facingTarget()
    if not target or target.kind ~= 'plot' then return nil end
    local action = self:plotAction(target.plot)
    if action == 'till' then return 'tool-shovel'
    elseif action == 'plant' then return 'seedbag-' .. Farm.pickSeed(self.gameData, self.selectedSeed)
    elseif action == 'water' then return 'tool-can'
    elseif action == 'harvest' then return 'tool-sickle'
    end
    return nil
end

-- Use a target (plot, villager or seed stall). Returns the action taken:
-- 'till' | 'plant' | 'water' | 'harvest' | 'sell' | 'buy' | 'growing' |
-- 'no-seeds' | 'no-crops' | 'no-coins' | nil.
-- 'oversell' means this attempt started the break. While the break plays
-- nothing can be used (returns nil).
function FarmState:interact(target)
    if not target or self.breaking then return nil end
    local data = self.gameData

    if target.kind == 'plot' then
        local plot = target.plot
        local action = self:plotAction(plot)
        if action == 'till' then
            Farm.till(plot)
            gSounds['till']:play()
            self:emit('till', plot.col, plot.row)
            self:popup('tilled', plot.col, plot.row, {0.9, 0.75, 0.5, 1})
            return 'till'
        elseif action == 'plant' then
            local _, seedType = Farm.plant(plot, data, self.selectedSeed)
            self.selectedSeed = seedType
            gSounds['plant']:play()
            self:emit('plant', plot.col, plot.row)
            self:popup('-1 ' .. SeedName(seedType), plot.col, plot.row)
            return 'plant'
        elseif action == 'no-seeds' then
            gSounds['deny']:play()
            self:popup('no seeds', plot.col, plot.row, {1, 0.5, 0.5, 1})
            return 'no-seeds'
        elseif action == 'water' then
            Farm.water(plot)
            gSounds['water']:play()
            self:emit('water', plot.col, plot.row)
            self:popup('watered', plot.col, plot.row, {0.55, 0.8, 1, 1})
            return 'water'
        elseif action == 'harvest' then
            local _, seedType = Farm.harvest(plot, data)
            gSounds['harvest']:play()
            self:emit('harvest', plot.col, plot.row)
            self:popup('+1 ' .. SeedName(seedType), plot.col, plot.row, {0.7, 1, 0.6, 1})
            -- the crop (already counted) pops off the plot and flies to its slot
            local px, py = FarmTileToPixel(plot.col, plot.row)
            local tx, ty = self:produceSlotCenter(seedType)
            self.juice:fly(gTextures['produce-' .. seedType], px + FARM_TILE / 2, py + FARM_TILE / 2, tx, ty,
                function() self.juice:pop('slot-' .. seedType, 0.5) end)
            return 'harvest'
        end
        self:popup('growing...', plot.col, plot.row, {0.85, 0.85, 0.85, 1})
        return 'growing'
    elseif target.kind == 'villager' then
        if Farm.isOverSell(data) and not data.hasBroken then
            -- sold out after a real sale: the villager pays for a crop that
            -- isn't there, and the farm breaks
            self:popup('+?c', FARM_VILLAGER.col, FARM_VILLAGER.row, {1, 0.3, 0.9, 1})
            self:say('Thanks! A nil!', FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME)
            self:startBreak('oversell')
            return 'oversell'
        end
        local ok, seedType, value = Farm.sell(data)
        if ok then
            gSounds['sell']:play()
            self:emit('sell', FARM_VILLAGER.col, FARM_VILLAGER.row)
            self.juice:burst('coins', self:coinIconCenter())
            self:popup('+' .. value .. 'c', FARM_VILLAGER.col, FARM_VILLAGER.row, {1, 0.9, 0.3, 1})
            if Farm.totalCrops(data) > 0 then
                self:say('Thanks! A ' .. SeedName(seedType) .. '!')
            else
                self:say('Thanks! Got another?')
            end
            self.idleTimer = 0
            self.nagTimer = FARM_VILLAGER_NAG_INTERVAL
            return 'sell'
        end
        gSounds['deny']:play()
        self:say('Got any crops?')
        return 'no-crops'
    elseif target.kind == 'shop' then
        -- buys one seed of the selected type; never touches the break timers
        local seedType = self.selectedSeed
        local ok, _, price = Farm.buySeed(data, seedType)
        if ok then
            gSounds['buy']:play()
            self:emit('buy', FARM_SHOP.col, FARM_SHOP.row)
            self:popup('+1 ' .. SeedName(seedType) .. ' -' .. price .. 'c', FARM_SHOP.col, FARM_SHOP.row, {0.7, 1, 0.6, 1})
            return 'buy'
        end
        gSounds['deny']:play()
        self:popup('need ' .. tostring(price or '?') .. 'c', FARM_SHOP.col, FARM_SHOP.row, {1, 0.5, 0.5, 1})
        return 'no-coins'
    end
    return nil
end

-- The break --------------------------------------------------------------------

-- Starts the glitch sequence. It plays once per game (gameData.hasBroken), so
-- later calls return false. `reason` is 'oversell' or 'idle'.
function FarmState:startBreak(reason)
    if self.breaking or self.gameData.hasBroken then return false end
    self.breaking = true
    self.breakReason = reason
    self.gameData.hasBroken = true
    self.heldDir = nil
    self.hover = nil
    self.juice:clearActions()             -- only the break's own effects from here
    if reason == 'idle' then
        self:say('Hm? Is something... wrong?', FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME)
    end

    local music = gSounds['farm-music']
    if music then music:stop() end
    gSounds['glitch']:play()

    -- 1) shake and corruption ramp up; 2) the farmer falls; 3) done. The last
    -- timer only sets a flag: changing state from inside a Timer callback
    -- would clear this group while Timer.update is iterating it.
    local group = self.breakTimers
    Timer.tween(FARM_BREAK_GLITCH_TIME, {
        [self.fx] = {shake = FARM_BREAK_SHAKE, corruption = 1},
    }):group(group)
    Timer.after(FARM_BREAK_GLITCH_TIME, function()
        gSounds['glitch']:play()
        Timer.tween(FARM_BREAK_FALL_TIME, {[self.fx] = {fall = 1}}):group(group)
    end):group(group)
    Timer.after(FARM_BREAK_GLITCH_TIME + FARM_BREAK_FALL_TIME, function()
        self.breakDone = true
    end):group(group)
    return true
end

-- While the break plays: advance the sequence only (growth is frozen and all
-- input, including the debug key, is ignored), then change state exactly once.
function FarmState:updateBreak(dt)
    Timer.update(dt, self.breakTimers)
    self:updateEffects(dt)
    if self.breakDone and not self.transitioned then
        self.transitioned = true
        gStateMachine:change('backrooms', CarryOverGameData(self.gameData))
    end
end

-- Villager requests and the idle fallback; only active after a sale.
function FarmState:updateVillager(dt)
    local data = self.gameData
    if not data.hasSold then return end

    self.idleTimer = self.idleTimer + dt
    if self.idleTimer >= FARM_IDLE_BREAK_TIME then
        self:startBreak('idle')
        return
    end

    -- out of stock: keep asking for more
    if Farm.totalCrops(data) == 0 then
        self.nagTimer = self.nagTimer - dt
        if self.nagTimer <= 0 then
            self.nagIndex = self.nagIndex % #FARM_VILLAGER_REQUESTS + 1
            self:say(FARM_VILLAGER_REQUESTS[self.nagIndex])
            self.nagTimer = FARM_VILLAGER_NAG_INTERVAL
        end
    end
end

-- Update -----------------------------------------------------------------------

function FarmState:updateEffects(dt)
    self.juice:update(dt)
    -- coin ticker: the shown amount eases toward the real one (which is never
    -- delayed), with a soft tick each time the shown number changes
    local before = math.floor(self.displayCoins + 0.5)
    self.displayCoins = Fx.tickToward(self.displayCoins, self.gameData.coins or 0, dt)
    self.coinTickTimer = self.coinTickTimer - dt
    if math.floor(self.displayCoins + 0.5) ~= before and self.coinTickTimer <= 0 and not self.breaking then
        gSounds['coin']:play()
        self.coinTickTimer = FX_COIN_TICK_INTERVAL
    end
    if self.villagerLine then
        self.villagerLine.time = self.villagerLine.time - dt
        if self.villagerLine.time <= 0 then self.villagerLine = nil end
    end
end

-- Advances every growing plot (never called during the break).
-- A stage change squashes the plot's sprite; maturity adds a sparkle.
function FarmState:updateGrowth(dt)
    for _, plot in ipairs(self.plots) do
        local stage = Farm.advance(plot, dt)
        if stage then
            self.juice:squash('crop-' .. plot.col .. ',' .. plot.row)
            if stage >= FARM_GROWTH_STAGES then
                local x, y = FarmTileToPixel(plot.col, plot.row)
                self.juice:burst('mature', x + FARM_TILE / 2, y + FARM_TILE / 2)
            end
        end
    end
end

function FarmState:updateMovement(dt)
    for _, dir in ipairs(DIR_ORDER) do
        if anyPressed(FARM_KEYS[dir]) then
            self:tryMove(dir)
            self.heldDir = dir
            self.repeatTimer = FARM_MOVE_REPEAT_DELAY
            return
        end
    end

    -- holding a direction repeats the step
    if self.heldDir and anyDown(FARM_KEYS[self.heldDir]) then
        self.repeatTimer = self.repeatTimer - dt
        if self.repeatTimer <= 0 then
            self:tryMove(self.heldDir)
            self.repeatTimer = FARM_MOVE_REPEAT_INTERVAL
        end
    else
        self.heldDir = nil
    end
end

function FarmState:updateMouse()
    self.hover = nil
    if not love.mouse.getPosition then return end
    local gx, gy = push:toGame(love.mouse.getPosition())
    local col, row = FarmPixelToTile(gx, gy)
    if not col then return end
    self.hover = {col = col, row = row, x = gx, y = gy}

    if love.mouse.wasPressed(1) then
        -- seed slots in the top bar
        if row == 1 then
            local slots = self:hudLayout().seeds
            for i, seedType in ipairs(SEED_TYPES) do
                local r = slots[i]
                if gx >= r.x and gx < r.x + r.w then
                    self:selectSeed(seedType)
                    return
                end
            end
        end
        self:interact(self:targetAt(col, row))
    end
end

function FarmState:update(dt)
    if self.breaking then
        self:updateBreak(dt)
        return
    end

    Timer.update(dt, self.timers)
    self:updateGrowth(dt)

    if IsDebugAdvancePressed() then
        -- same seeds-only hand-off as the real break, so coins/crops never leak
        gStateMachine:change('backrooms', CarryOverGameData(self.gameData))
        return
    end

    for i, seedType in ipairs(SEED_TYPES) do
        if love.keyboard.wasPressed(tostring(i)) or love.keyboard.wasPressed('kp' .. i) then
            self:selectSeed(seedType)
        end
    end
    if anyPressed(FARM_KEYS.nextSeed) then self:cycleSeed() end

    self:updateMovement(dt)
    if anyPressed(FARM_KEYS.interact) then
        self:interact(self:facingTarget())
    end
    if self.breaking then return end      -- that press started the break
    self:updateMouse()
    if self.breaking then return end      -- so did that click

    -- ease the drawn position toward the tile for smooth steps
    local tx, ty = FarmTileToPixel(self.player.col, self.player.row)
    local k = math.min(1, dt * 18)
    self.player.drawX = self.player.drawX + (tx - self.player.drawX) * k
    self.player.drawY = self.player.drawY + (ty - self.player.drawY) * k

    self.time = self.time + dt
    self.dayTime = self.dayTime + dt
    self:updateEffects(dt)
    self:updateVillager(dt)
end

-- Day cycle: phase 0..1 within the current day (0 = dawn), the day number
-- (1 on a new farm, +1 at each dawn) and the tint for the current phase.
function FarmState:dayPhase()
    return (self.dayTime % FARM_DAY_LENGTH) / FARM_DAY_LENGTH
end

function FarmState:dayNumber()
    return math.floor(self.dayTime / FARM_DAY_LENGTH) + 1
end

function FarmState:dayTint()
    return FarmDayTint(self:dayPhase())
end

-- Bottom-bar hint for the seed stall: the selected type and its price.
function FarmState:shopHint()
    local seedType = self.selectedSeed
    local price = SEED_PRICES[seedType] or 0
    if (self.gameData.coins or 0) >= price then
        return '[E] buy ' .. SeedName(seedType) .. ' seed (' .. price .. 'c)'
    end
    return SeedName(seedType) .. ' seed costs ' .. price .. 'c (have ' .. (self.gameData.coins or 0) .. 'c)'
end

-- Context hint for the bottom bar, from the keyboard target. The seed stall
-- also shows its hint while the mouse hovers it.
function FarmState:hintText()
    local target = self:facingTarget()
    if (target and target.kind == 'shop') or (self.hover and self:isShopAt(self.hover.col, self.hover.row)) then
        return self:shopHint()
    end
    if target and target.kind == 'plot' then
        local plot = target.plot
        local action = self:plotAction(plot)
        if action == 'till' then return '[E] till the soil (shovel)'
        elseif action == 'plant' then
            return '[E] plant ' .. SeedName(Farm.pickSeed(self.gameData, self.selectedSeed)) .. ' (seed bag)'
        elseif action == 'no-seeds' then return 'no seeds left'
        elseif action == 'water' then return '[E] water ' .. SeedName(plot.seedType) .. ' (watering can)'
        elseif action == 'harvest' then return '[E] harvest ' .. SeedName(plot.seedType) .. ' (sickle)'
        end
        return SeedName(plot.seedType) .. ' growing...'
    elseif target and target.kind == 'villager' then
        local cropType = Farm.pickCrop(self.gameData)
        if cropType then
            return '[E] sell ' .. SeedName(cropType) .. ' (+' .. CROP_VALUES[cropType] .. 'c)'
        elseif self.gameData.hasSold then
            return '[E] sell another?'
        end
        return 'harvest a crop to sell'
    end
    return 'WASD/arrows move  E use  1-3 seed  or click'
end

-- Render -----------------------------------------------------------------------

-- Draws an image fitted into a `size` box at (x, y), scaled around its
-- centre by `pulse`, at `alpha`.
local function drawIcon(image, x, y, size, pulse, alpha)
    local iw, ih = image:getDimensions()
    local s = size / math.max(iw, ih) * (pulse or 1)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(image, x + size / 2, y + size / 2, 0, s, s, iw / 2, ih / 2)
end

local function drawSprite(image, x, y, tint, sx, sy, kx)
    -- draws an image scaled x2, bottom-centred in the tile at (x, y); sx/sy
    -- (optional) multiply the scale around the bottom centre (pops, squash);
    -- kx (optional) skews it around the bottom (ambient sway)
    local w, h = image:getDimensions()
    local scale = math.min(2, (FARM_TILE - 4) / math.max(w, h))
    love.graphics.setColor(tint or {1, 1, 1, 1})
    love.graphics.draw(image, x + FARM_TILE / 2, y + FARM_TILE - 2, 0, scale * (sx or 1), scale * (sy or 1), w / 2, h,
        kx or 0, 0)
end

-- A soft drop shadow under something standing on the tile at (x, y).
local function drawShadow(x, y, width)
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse('fill', x + FARM_TILE / 2, y + FARM_TILE - 3, (width or 20) / 2, 3)
end

local function drawTiled(image, x, y)
    local w, h = image:getDimensions()
    love.graphics.draw(image, x, y, 0, FARM_TILE / w, FARM_TILE / h)
end

-- Ambient sway (an x-skew) for something at `phase`; frozen with self.time
-- during the break. Never moves logical positions.
function FarmState:sway(phase)
    return math.sin((self.time or 0) * FARM_SWAY_SPEED + phase) * FARM_SWAY_SKEW
end

-- The three soil looks: untilled (pale, dry, flat), tilled (furrows),
-- watered (dark and wet).
function FarmState:renderSoil(plot, x, y)
    if not plot.tilled then
        love.graphics.setColor(0.86, 0.78, 0.6, 1)
        drawTiled(gTextures['soil'], x, y)
        love.graphics.setColor(0.35, 0.25, 0.15, 0.3)
        love.graphics.rectangle('line', x + 1.5, y + 1.5, FARM_TILE - 3, FARM_TILE - 3)
        return
    end
    local wet = plot.watered and plot.state ~= PLOT_EMPTY
    local k = wet and 0.62 or 1
    love.graphics.setColor(k, k * 0.95, wet and 0.66 or 1, 1)
    drawTiled(gTextures['soil'], x, y)
    drawTiled(gTextures['plot'], x, y)
    if wet then
        -- dark damp patches and a cool wet sheen
        love.graphics.setColor(0.18, 0.1, 0.1, 0.35)
        love.graphics.rectangle('fill', x + 3, y + 24, 9, 4)
        love.graphics.rectangle('fill', x + 20, y + 4, 8, 3)
        love.graphics.setColor(0.7, 0.82, 1, 0.6)
        love.graphics.rectangle('fill', x + 5, y + 6, 3, 1)
        love.graphics.rectangle('fill', x + 22, y + 23, 3, 1)
        love.graphics.rectangle('fill', x + 25, y + 12, 1, 1)
    end
end

function FarmState:renderPond()
    local set = {}
    for _, t in ipairs(FARM_DECOR.pond) do set[t[1] .. ',' .. t[2]] = true end
    local function has(c, r) return set[c .. ',' .. r] end
    -- insets only on sides without another pond tile, so the tiles merge
    local function insets(c, r)
        return has(c - 1, r) and 0 or 3, has(c + 1, r) and 0 or 3, has(c, r - 1) and 0 or 4, has(c, r + 1) and 0 or 3
    end
    -- three passes (bank, water, highlights) so no tile's bank covers another's water
    for pass = 1, 3 do
        for _, t in ipairs(FARM_DECOR.pond) do
            local c, r = t[1], t[2]
            local x, y = FarmTileToPixel(c, r)
            local l, rr, u, d = insets(c, r)
            local w, h = FARM_TILE - l - rr, FARM_TILE - u - d
            if pass == 1 then
                love.graphics.setColor(0.2, 0.32, 0.22, 1)
                love.graphics.rectangle('fill', x + l - 1, y + u - 1, w + 2, h + 2, 4, 4)
            elseif pass == 2 then
                love.graphics.setColor(0.24, 0.5, 0.78, 1)
                love.graphics.rectangle('fill', x + l, y + u, w, h, 3, 3)
                if u > 0 then
                    love.graphics.setColor(0.17, 0.38, 0.62, 1)   -- shaded top bank edge
                    love.graphics.rectangle('fill', x + l, y + u, w, 2)
                end
            else
                -- shimmer: highlight pixels drifting with time
                local t0 = (self.time or 0) * FARM_POND_SHIMMER_SPEED
                for i = 0, 2 do
                    local px = x + l + 3 + ((i * 9 + c * 5 + math.floor(t0 * 4 + i * 3)) % math.max(1, w - 8))
                    local py = y + u + 5 + i * 6 + math.floor(math.sin(t0 + i + r) + 0.5)
                    love.graphics.setColor(0.85, 0.95, 1, 0.55 + 0.35 * math.sin(t0 * 2 + i * 2 + c))
                    love.graphics.rectangle('fill', px, py, 3, 1)
                end
            end
        end
    end
end

function FarmState:renderField()
    love.graphics.setColor(1, 1, 1, 1)
    for row = 1, FARM_ROWS do
        for col = 1, FARM_COLS do
            local x, y = FarmTileToPixel(col, row)
            drawTiled(gTextures['grass'], x, y)
        end
    end

    -- dirt path to the villager and the stall
    for _, t in ipairs(FARM_DECOR.path) do
        local x, y = FarmTileToPixel(t[1], t[2])
        love.graphics.setColor(1, 0.94, 0.82, 1)
        drawTiled(gTextures['path'], x, y)
    end

    -- ground variation: swaying tufts and small stones
    for _, g in ipairs(self.groundDecor) do
        local x, y = FarmTileToPixel(g.col, g.row)
        x, y = x + g.x, y + g.y
        if g.kind == 'tuft' then
            local lean = math.floor(self:sway(g.phase) * 20 + 0.5)
            love.graphics.setColor(0.22, 0.45, 0.2, 1)
            love.graphics.rectangle('fill', x, y - 3, 1, 3)
            love.graphics.rectangle('fill', x + 2, y - 4, 1, 4)
            love.graphics.setColor(0.45, 0.72, 0.32, 1)
            love.graphics.rectangle('fill', x + lean, y - 4, 1, 1)
            love.graphics.rectangle('fill', x + 2 + lean, y - 5, 1, 1)
            love.graphics.rectangle('fill', x + 1, y - 2, 1, 2)
        else
            love.graphics.setColor(0.35, 0.36, 0.38, 1)
            love.graphics.rectangle('fill', x, y, g.big and 3 or 2, 2)
            love.graphics.setColor(0.62, 0.63, 0.62, 1)
            love.graphics.rectangle('fill', x, y, g.big and 2 or 1, 1)
        end
    end

    -- plots: soil look, then the crop with its shadow, pop, squash and sway
    for _, plot in ipairs(self.plots) do
        local x, y = FarmTileToPixel(plot.col, plot.row)
        self:renderSoil(plot, x, y)
        if plot.state ~= PLOT_EMPTY then
            local pop = self.juice:popScale(plot.col .. ',' .. plot.row)
            local sx, sy = self.juice:squashScale('crop-' .. plot.col .. ',' .. plot.row)
            drawShadow(x, y, 6 + plot.stage * 3)
            drawSprite(gTextures['crop-' .. plot.seedType .. '-' .. plot.stage], x, y, nil, sx * pop, sy * pop,
                self:sway(plot.col * 1.3 + plot.row))
        end
        if plot.state == PLOT_MATURE then
            -- small "ready" marker
            love.graphics.setColor(1, 1, 0.4, 1)
            love.graphics.circle('fill', x + FARM_TILE - 5, y + 5, 3)
        end
    end

    self:renderPond()

    -- solid dressing, back to front
    local barn = gTextures['barn']
    local bw, bh = barn:getDimensions()
    local bx, by = FarmTileToPixel(FARM_DECOR.barn.col, FARM_DECOR.barn.row)
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse('fill', bx + bw / 2, by + FARM_TILE - 3, bw / 2 - 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(barn, bx, by + FARM_TILE - bh * (96 / bh), 0, 96 / bw, 96 / bh)

    for _, t in ipairs(FARM_DECOR.fence) do
        local x, y = FarmTileToPixel(t[1], t[2])
        local img = gTextures['fence']
        local w, h = img:getDimensions()
        love.graphics.setColor(0, 0, 0, 0.18)
        love.graphics.rectangle('fill', x + FARM_TILE / 2 - 3, y + 2, 8, FARM_TILE - 2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x + FARM_TILE / 2 - w, y, 0, 2, FARM_TILE / h)
    end
    for _, t in ipairs(FARM_DECOR.well) do
        local x, y = FarmTileToPixel(t[1], t[2])
        drawShadow(x, y, 26)
        drawSprite(gTextures['well'], x, y)
    end
    for i, t in ipairs(FARM_DECOR.bushes) do
        local x, y = FarmTileToPixel(t[1], t[2])
        drawShadow(x, y, 22)
        drawSprite(gTextures[i % 2 == 0 and 'bush-2' or 'bush-1'], x, y, nil, 1, 1, self:sway(i * 2.1))
    end

    -- the villager hops after a sale (its tile's pop, see FarmState:emit)
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    drawShadow(vx, vy, 18)
    drawSprite(gTextures['villager'], vx, vy + self:villagerHop())

    self:renderShop()
end

-- The seed stall: a wooden counter with the selected type's seed bag on it
-- and its price.
function FarmState:renderShop()
    local x, y = FarmTileToPixel(FARM_SHOP.col, FARM_SHOP.row)
    drawShadow(x, y + 2, 30)
    -- awning and counter
    love.graphics.setColor(0.75, 0.25, 0.2, 1)
    love.graphics.rectangle('fill', x + 2, y + 2, FARM_TILE - 4, 6)
    love.graphics.setColor(0.95, 0.9, 0.8, 1)
    for i = 0, 2 do love.graphics.rectangle('fill', x + 6 + i * 8, y + 2, 4, 6) end
    love.graphics.setColor(0.45, 0.3, 0.17, 1)
    love.graphics.rectangle('fill', x + 3, y + 8, 2, 14)
    love.graphics.rectangle('fill', x + FARM_TILE - 5, y + 8, 2, 14)
    love.graphics.setColor(0.6, 0.4, 0.22, 1)
    love.graphics.rectangle('fill', x + 2, y + 20, FARM_TILE - 4, 10)
    -- the selected seed bag on the counter
    love.graphics.setColor(1, 1, 1, 1)
    local icon = gTextures['seedbag-' .. self.selectedSeed]
    if icon then
        local iw, ih = icon:getDimensions()
        love.graphics.draw(icon, x + FARM_TILE / 2 - 7, y + 8, 0, 14 / iw, 14 / ih)
    end
    love.graphics.setFont(gFonts['small'])
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.printf((SEED_PRICES[self.selectedSeed] or 0) .. 'c', x, y + 21, FARM_TILE, 'center')
end

function FarmState:renderHighlights()
    love.graphics.setLineWidth(1)
    local target = self:facingTarget()
    if target then
        local x, y = FarmTileToPixel(target.col, target.row)
        love.graphics.setColor(1, 0.95, 0.3, 1)
        love.graphics.rectangle('line', x + 1.5, y + 1.5, FARM_TILE - 3, FARM_TILE - 3)
    end
    if self.hover and self:targetAt(self.hover.col, self.hover.row) then
        local x, y = FarmTileToPixel(self.hover.col, self.hover.row)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle('line', x + 3.5, y + 3.5, FARM_TILE - 7, FARM_TILE - 7)
    end
end

-- Vertical offset of the villager's sale bounce (0 at rest, negative = up).
function FarmState:villagerHop()
    local pop = self.juice:popScale(FARM_VILLAGER.col .. ',' .. FARM_VILLAGER.row)
    return -math.floor((pop - 1) * FARM_VILLAGER_HOP + 0.5)
end

-- The tool for the faced plot, small beside the farmer with a gentle bob.
function FarmState:renderTool()
    local key = self:toolIcon()
    if not key or not gTextures[key] then return end
    local p = self.player
    local bob = math.floor(math.sin((self.time or 0) * 4) + 0.5)
    -- held at the farmer's right side, mostly outside the sprite
    local x = p.drawX + FARM_TILE - 9
    local y = p.drawY + 12 + bob
    drawIcon(gTextures[key], x, y, FARM_TOOL_ICON_SIZE, 1, 1)
end

-- `dy` and `rotation` (optional) are used by the fall.
function FarmState:renderPlayer(dy, rotation)
    local p = self.player
    local image = gTextures['hero']
    local w, h = image:getDimensions()
    local scale = math.min(2, (FARM_TILE - 4) / math.max(w, h))
    local flip = p.facing == 'left' and -1 or 1
    if not dy then drawShadow(p.drawX, p.drawY, 18) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, p.drawX + FARM_TILE / 2, p.drawY + FARM_TILE - 2 + (dy or 0),
        rotation or 0, scale * flip, scale, w / 2, h)
end

function FarmState:renderVillagerLine()
    local text = self.villagerLine and self.villagerLine.text
    if not text then
        if Farm.totalCrops(self.gameData) > 0 then
            text = 'Buying crops!'
        else
            text = self.gameData.hasSold and 'More crops?' or 'Crops?'
        end
    end
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    local font = gFonts['small']
    local w = font:getWidth(text) + 8
    local bx = math.max(2, math.min(VIRTUAL_WIDTH - w - 2, vx + FARM_TILE / 2 - w / 2))
    local by = vy - 16 + self:villagerHop()
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle('fill', bx, by, w, 13, 3, 3)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.setFont(font)
    love.graphics.print(text, bx + 4, by + 2)
end

-- Rectangles of the top-bar elements (virtual px), from FARM_HUD: seed
-- slots (bag icon, key number above the count), a divider, produce slots
-- (icon and count), the coin icon and amount, and the day number
-- (right-aligned at day.right). Text positions are top-left corners.
function FarmState:hudLayout()
    local L = FARM_HUD
    local layout = {seeds = {}, produce = {}}
    local x = L.left
    for i = 1, #SEED_TYPES do
        layout.seeds[i] = {x = x, y = L.top, w = L.seedSlotW, h = L.height,
            icon = {x = x + 2, y = L.top + 4, size = L.seedIcon}, iconSize = L.seedIcon,
            key = {x = x + L.seedIcon + 5, y = L.top + 1}, count = {x = x + L.seedIcon + 4, y = L.top + 11}}
        x = x + L.seedSlotW
    end
    layout.divider = {x = x + L.gap, y = L.top + 2, w = 1, h = L.height - 4}
    x = x + L.gap * 2 + 1
    for i = 1, #SEED_TYPES do
        layout.produce[i] = {x = x, y = L.top, w = L.produceSlotW, h = L.height,
            icon = {x = x + 1, y = L.top + 6, size = L.produceIcon}, iconSize = L.produceIcon,
            count = {x = x + L.produceIcon + 3, y = L.top + 8}}
        x = x + L.produceSlotW
    end
    layout.coinIcon = {x = x + L.gap, y = L.top + 7, w = L.coinIcon, h = L.coinIcon}
    layout.coinText = {x = x + L.gap + L.coinIcon + 3, y = L.top + 8}
    layout.day = {right = VIRTUAL_WIDTH - L.left, y = L.top + 8}
    layout.bar = {x = 0, y = 0, w = VIRTUAL_WIDTH, h = FARM_TILE - 4}
    return layout
end

-- A small gold coin drawn in code (the pack has no coin sprite).
local function drawCoin(r, scale)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    local rad = r.w / 2 * (scale or 1)
    love.graphics.setColor(0.45, 0.28, 0.05, 1)
    love.graphics.circle('fill', cx, cy, rad)
    love.graphics.setColor(1, 0.82, 0.25, 1)
    love.graphics.circle('fill', cx, cy, rad - 1)
    love.graphics.setColor(1, 0.95, 0.6, 1)
    love.graphics.rectangle('fill', math.floor(cx - 1), math.floor(cy - rad + 2), 1, 2)
    love.graphics.setColor(0.8, 0.55, 0.1, 1)
    love.graphics.rectangle('fill', math.floor(cx), math.floor(cy - 1), 1, 3)
end

function FarmState:renderHUD()
    local data = self.gameData
    local layout = self:hudLayout()
    local font = gFonts['small']
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle('fill', 0, 0, VIRTUAL_WIDTH, FARM_TILE - 4)
    love.graphics.setFont(font)
    local dim = FARM_HUD.emptyAlpha

    -- seed bags: dimmed when empty; the selected slot is always outlined
    for i, seedType in ipairs(SEED_TYPES) do
        local r = layout.seeds[i]
        local n = data.seeds[seedType] or 0
        local a = n > 0 and 1 or dim
        if seedType == self.selectedSeed then
            love.graphics.setColor(1, 0.95, 0.3, 1)
            love.graphics.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 2, r.h - 1)
        end
        drawIcon(gTextures['seedbag-' .. seedType], r.icon.x, r.icon.y, r.icon.size, 1, a)
        love.graphics.setColor(0.75, 0.75, 0.75, a)
        love.graphics.print(tostring(i), r.key.x, r.key.y)
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.print('x' .. n, r.count.x, r.count.y)
    end

    -- divider between the seed group and the produce group
    local d = layout.divider
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle('fill', d.x, d.y, d.w, d.h)

    -- harvested produce: dimmed when none; pulses when a flying crop lands
    for i, seedType in ipairs(SEED_TYPES) do
        local r = layout.produce[i]
        local n = data.crops[seedType] or 0
        local a = n > 0 and 1 or dim
        drawIcon(gTextures['produce-' .. seedType], r.icon.x, r.icon.y, r.icon.size,
            self.juice:popScale('slot-' .. seedType), a)
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.print(tostring(n), r.count.x, r.count.y)
    end

    -- coins: an icon and the ticking amount, pulsing while it changes
    local shown = math.floor(self.displayCoins + 0.5)
    local ticking = self.displayCoins ~= (data.coins or 0)
    local pulse = ticking and (1 + 0.15 * math.abs(math.sin((self.time or 0) * 18))) or 1
    drawCoin(layout.coinIcon, pulse)
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.print(tostring(shown), layout.coinText.x, layout.coinText.y)

    -- day number
    local dayText = 'Day ' .. self:dayNumber()
    love.graphics.setColor(0.85, 0.9, 1, 1)
    love.graphics.print(dayText, layout.day.right - font:getWidth(dayText), layout.day.y)

    -- bottom hint bar
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle('fill', 0, VIRTUAL_HEIGHT - 16, VIRTUAL_WIDTH, 16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self:hintText(), 0, VIRTUAL_HEIGHT - 12, VIRTUAL_WIDTH, 'center')
    if DEBUG_MODE then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print(DEBUG_ADVANCE_KEY, VIRTUAL_WIDTH - 14, VIRTUAL_HEIGHT - 12)
    end
end

-- Corrupted blocks and horizontal tears, scaled by fx.corruption.
local CORRUPTION_COLORS = {
    {1, 0, 1}, {0, 1, 1}, {0.95, 0.9, 0.45}, {0, 0, 0}, {1, 1, 1},
}
function FarmState:renderCorruption()
    local n = math.floor(self.fx.corruption * FARM_BREAK_CORRUPTION_BLOCKS)
    for _ = 1, n do
        local c = CORRUPTION_COLORS[math.random(#CORRUPTION_COLORS)]
        love.graphics.setColor(c[1], c[2], c[3], 0.4 + math.random() * 0.5)
        if math.random() < 0.3 then
            love.graphics.rectangle('fill', 0, math.random(0, VIRTUAL_HEIGHT), VIRTUAL_WIDTH,
                math.random(1, 4))
        else
            love.graphics.rectangle('fill', math.random(0, VIRTUAL_WIDTH - 8),
                math.random(0, VIRTUAL_HEIGHT - 8), math.random(4, 40), math.random(2, 16))
        end
    end
end

-- Draws `drawScene` either into the farm canvas and then through the shader
-- (into push's canvas), or, without the pass, straight through followed by a
-- multiply overlay of the day tint (skipped when `plain`).
function FarmState:drawThroughPass(drawScene, plain)
    if FarmShader.init() then
        local target = love.graphics.getCanvas()
        love.graphics.push('all')
        love.graphics.setCanvas(FarmShader.canvas)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 1)
        drawScene()
        love.graphics.pop()
        love.graphics.setCanvas(target)
        FarmShader.send(FarmShader.uniforms({time = self.time, tint = self:dayTint(), plain = plain}))
        love.graphics.setShader(FarmShader.shader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(FarmShader.canvas, 0, 0)
        love.graphics.setShader()
        return true
    end
    drawScene()
    if not plain then
        local t = self:dayTint()
        love.graphics.setBlendMode('multiply', 'premultiplied')
        love.graphics.setColor(t[1], t[2], t[3], 1)
        love.graphics.rectangle('fill', 0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
        love.graphics.setBlendMode('alpha')
    end
    return false
end

-- The break: the shaking farm lurches up and away while the farmer drops
-- through it, corruption spreads, and the screen fades to black. The scene
-- goes through the pass with the tint and every lighting effect zeroed; the
-- corruption and the fade are drawn on top, outside it, so nothing softens
-- or hides them.
function FarmState:renderBreak()
    local fx = self.fx
    local sx = (math.random() * 2 - 1) * fx.shake
    local sy = (math.random() * 2 - 1) * fx.shake
    local drop = fx.fall * fx.fall

    self:drawThroughPass(function()
        love.graphics.push()
        love.graphics.translate(sx, sy - drop * VIRTUAL_HEIGHT * 0.5)
        self:renderField()
        self:renderVillagerLine()
        love.graphics.pop()

        love.graphics.push()
        love.graphics.translate(sx, sy)
        self:renderPlayer(drop * VIRTUAL_HEIGHT, fx.fall * 6)
        self:renderHUD()
        love.graphics.pop()
    end, true)

    self:renderCorruption()
    love.graphics.setColor(0, 0, 0, fx.fall)
    love.graphics.rectangle('fill', 0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)
end

-- The field, characters and effects go through the post-process pass; the
-- speech bubble, popups, HUD and flying pickups are drawn after it, so text
-- stays crisp and readable at night.
function FarmState:render()
    if self.breaking then
        self:renderBreak()
        return
    end

    self:drawThroughPass(function()
        self:renderField()
        self:renderHighlights()
        self:renderPlayer()
        self:renderTool()
        self.juice:drawParticles()
    end)

    self:renderVillagerLine()
    self.juice:drawPopups(gFonts['small'])
    self:renderHUD()
    self.juice:drawFlyers()               -- harvested crops fly into the HUD
    love.graphics.setColor(1, 1, 1, 1)
end
