-- 2D farm. Renders through push at the 320x320 virtual resolution.
--
-- Controls (keyboard): WASD/arrows move the farmer one tile per press (hold
-- to repeat); E/Space/Enter uses the tile the farmer faces (plant, harvest,
-- sell); 1-3 pick a seed type, Tab/Q cycles it.
-- Controls (mouse): hover highlights a plot or the villager, left click uses
-- it directly; clicking a seed slot in the top bar selects that seed.
--
-- Rules live in src/Farm.lua; growth runs on a knife Timer group owned by this
-- state, so it only advances while the farm is active.
FarmState = Class{__includes = BaseState}

FarmState.usesPush = true

local DIRS = {
    up = {0, -1},
    down = {0, 1},
    left = {-1, 0},
    right = {1, 0},
}
local DIR_ORDER = {'up', 'down', 'left', 'right'}

-- HUD seed slots: x position and width in the top bar
local SEED_SLOT_X, SEED_SLOT_W = 4, 46

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
    self.popups = {}                      -- floating feedback text
    self.villagerLine = nil               -- {text, time left}

    local music = gSounds['farm-music']
    if music then music:setLooping(true); music:play() end
end

function FarmState:exit()
    Timer.clear(self.timers)
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

-- What the player can use at a tile: {kind = 'plot', plot} or
-- {kind = 'villager'} or nil.
function FarmState:targetAt(col, row)
    if not col then return nil end
    local plot = self:plotAt(col, row)
    if plot then return {kind = 'plot', plot = plot, col = col, row = row} end
    if self:isVillagerAt(col, row) then return {kind = 'villager', col = col, row = row} end
    return nil
end

function FarmState:isWalkable(col, row)
    if col < 1 or col > FARM_COLS or row < FARM_FIELD_TOP or row > FARM_FIELD_BOTTOM then
        return false
    end
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
    self.popups[#self.popups + 1] = {text = text, x = x + FARM_TILE / 2, y = y, life = 1.2,
        color = color or {1, 1, 1, 1}}
end

function FarmState:say(text, duration)
    self.villagerLine = {text = text, time = duration or 2.5}
end

-- Use a target (plot or villager). Returns the action taken:
-- 'plant' | 'harvest' | 'sell' | 'growing' | 'no-seeds' | 'no-crops' | nil.
function FarmState:interact(target)
    if not target then return nil end
    local data = self.gameData

    if target.kind == 'plot' then
        local plot = target.plot
        if plot.state == PLOT_EMPTY then
            local ok, seedType = Farm.plant(plot, data, self.selectedSeed, self.timers)
            if ok then
                self.selectedSeed = seedType
                gSounds['plant']:play()
                self:popup('-1 ' .. seedType, plot.col, plot.row)
                return 'plant'
            end
            gSounds['deny']:play()
            self:popup('no seeds', plot.col, plot.row, {1, 0.5, 0.5, 1})
            return 'no-seeds'
        elseif plot.state == PLOT_MATURE then
            local _, seedType = Farm.harvest(plot, data)
            gSounds['harvest']:play()
            self:popup('+1 ' .. seedType, plot.col, plot.row, {0.7, 1, 0.6, 1})
            return 'harvest'
        else
            self:popup('growing...', plot.col, plot.row, {0.85, 0.85, 0.85, 1})
            return 'growing'
        end
    elseif target.kind == 'villager' then
        local ok, seedType, value = Farm.sell(data)
        if ok then
            gSounds['sell']:play()
            self:popup('+' .. value .. 'c', FARM_VILLAGER.col, FARM_VILLAGER.row, {1, 0.9, 0.3, 1})
            self:say('Thanks! A ' .. seedType .. '!')
            return 'sell'
        end
        gSounds['deny']:play()
        self:say('Got any crops?')
        return 'no-crops'
    end
    return nil
end

-- Update -----------------------------------------------------------------------

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
            for i, seedType in ipairs(SEED_TYPES) do
                local sx = SEED_SLOT_X + (i - 1) * SEED_SLOT_W
                if gx >= sx and gx < sx + SEED_SLOT_W then
                    self:selectSeed(seedType)
                    return
                end
            end
        end
        self:interact(self:targetAt(col, row))
    end
end

function FarmState:update(dt)
    Timer.update(dt, self.timers)

    if IsDebugAdvancePressed() then
        gStateMachine:change('backrooms', self.gameData)
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
    self:updateMouse()

    -- ease the drawn position toward the tile for smooth steps
    local tx, ty = FarmTileToPixel(self.player.col, self.player.row)
    local k = math.min(1, dt * 18)
    self.player.drawX = self.player.drawX + (tx - self.player.drawX) * k
    self.player.drawY = self.player.drawY + (ty - self.player.drawY) * k

    for i = #self.popups, 1, -1 do
        local p = self.popups[i]
        p.life = p.life - dt
        p.y = p.y - dt * 16
        if p.life <= 0 then table.remove(self.popups, i) end
    end
    if self.villagerLine then
        self.villagerLine.time = self.villagerLine.time - dt
        if self.villagerLine.time <= 0 then self.villagerLine = nil end
    end
end

-- Context hint for the bottom bar, from the keyboard target.
function FarmState:hintText()
    local target = self:facingTarget()
    if target and target.kind == 'plot' then
        local plot = target.plot
        if plot.state == PLOT_EMPTY then
            local seedType = Farm.pickSeed(self.gameData, self.selectedSeed)
            return seedType and ('[E] plant ' .. seedType) or 'no seeds left'
        elseif plot.state == PLOT_MATURE then
            return '[E] harvest ' .. plot.seedType
        end
        return plot.seedType .. ' growing...'
    elseif target and target.kind == 'villager' then
        local cropType = Farm.pickCrop(self.gameData)
        if cropType then
            return '[E] sell ' .. cropType .. ' (+' .. CROP_VALUES[cropType] .. 'c)'
        end
        return 'harvest a crop to sell'
    end
    return 'WASD/arrows move  E use  1-3 seed  or click'
end

-- Render -----------------------------------------------------------------------

local function drawSprite(image, x, y, tint)
    -- draws an image scaled x2, bottom-centred in the tile at (x, y)
    local w, h = image:getDimensions()
    local scale = math.min(2, (FARM_TILE - 4) / math.max(w, h))
    love.graphics.setColor(tint or {1, 1, 1, 1})
    love.graphics.draw(image, x + FARM_TILE / 2, y + FARM_TILE - 2, 0, scale, scale, w / 2, h)
end

local function drawTiled(image, x, y)
    local w, h = image:getDimensions()
    love.graphics.draw(image, x, y, 0, FARM_TILE / w, FARM_TILE / h)
end

function FarmState:renderField()
    love.graphics.setColor(1, 1, 1, 1)
    for row = 1, FARM_ROWS do
        for col = 1, FARM_COLS do
            local x, y = FarmTileToPixel(col, row)
            drawTiled(gTextures['grass'], x, y)
        end
    end

    for _, plot in ipairs(self.plots) do
        local x, y = FarmTileToPixel(plot.col, plot.row)
        love.graphics.setColor(1, 1, 1, 1)
        drawTiled(gTextures['soil'], x, y)
        drawTiled(gTextures['plot'], x, y)
        if plot.state ~= PLOT_EMPTY then
            drawSprite(gTextures['crop-' .. plot.seedType .. '-' .. plot.stage], x, y)
        end
        if plot.state == PLOT_MATURE then
            -- small "ready" marker
            love.graphics.setColor(1, 1, 0.4, 1)
            love.graphics.circle('fill', x + FARM_TILE - 5, y + 5, 3)
        end
    end

    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    drawSprite(gTextures['villager'], vx, vy, {0.85, 0.7, 1, 1})
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

function FarmState:renderPlayer()
    local p = self.player
    local image = gTextures['hero']
    local w, h = image:getDimensions()
    local scale = math.min(2, (FARM_TILE - 4) / math.max(w, h))
    local flip = p.facing == 'left' and -1 or 1
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, p.drawX + FARM_TILE / 2, p.drawY + FARM_TILE - 2, 0,
        scale * flip, scale, w / 2, h)
end

function FarmState:renderVillagerLine()
    local text = self.villagerLine and self.villagerLine.text
    if not text then
        text = Farm.totalCrops(self.gameData) > 0 and 'Buying crops!' or 'Crops?'
    end
    local vx, vy = FarmTileToPixel(FARM_VILLAGER.col, FARM_VILLAGER.row)
    local font = gFonts['small']
    local w = font:getWidth(text) + 8
    local bx = math.max(2, math.min(VIRTUAL_WIDTH - w - 2, vx + FARM_TILE / 2 - w / 2))
    local by = vy - 16
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle('fill', bx, by, w, 13, 3, 3)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.setFont(font)
    love.graphics.print(text, bx + 4, by + 2)
end

function FarmState:renderHUD()
    local data = self.gameData
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle('fill', 0, 0, VIRTUAL_WIDTH, FARM_TILE - 4)
    love.graphics.setFont(gFonts['small'])

    for i, seedType in ipairs(SEED_TYPES) do
        local x = SEED_SLOT_X + (i - 1) * SEED_SLOT_W
        if seedType == self.selectedSeed then
            love.graphics.setColor(1, 0.95, 0.3, 1)
            love.graphics.rectangle('line', x + 0.5, 2.5, SEED_SLOT_W - 3, FARM_TILE - 9)
        end
        love.graphics.setColor(1, 1, 1, 1)
        local icon = gTextures['seedbag-' .. seedType]
        local iw, ih = icon:getDimensions()
        love.graphics.draw(icon, x + 3, 5, 0, 16 / iw, 16 / ih)
        love.graphics.print(i .. ' x' .. (data.seeds[seedType] or 0), x + 21, 9)
    end

    -- harvested crops, then coins
    local x = 4 + #SEED_TYPES * SEED_SLOT_W + 6
    for _, seedType in ipairs(SEED_TYPES) do
        local icon = gTextures['produce-' .. seedType]
        local iw, ih = icon:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon, x, 8, 0, 12 / iw, 12 / ih)
        love.graphics.print('' .. (data.crops[seedType] or 0), x + 13, 10)
        x = x + 30
    end
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.print(data.coins .. 'c', x + 4, 10)

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

function FarmState:render()
    self:renderField()
    self:renderHighlights()
    self:renderPlayer()
    self:renderVillagerLine()

    love.graphics.setFont(gFonts['small'])
    for _, p in ipairs(self.popups) do
        local c = p.color
        love.graphics.setColor(c[1], c[2], c[3], math.min(1, p.life * 2))
        love.graphics.printf(p.text, p.x - 40, p.y, 80, 'center')
    end

    self:renderHUD()
    love.graphics.setColor(1, 1, 1, 1)
end
