-- 3D backrooms. Opts out of push: g3d draws straight to the screen at native
-- resolution with the window's depth buffer, then renderHUD draws 2D on top
-- with depth testing disabled (see love.draw in main.lua).
--
-- The player walks through BACKROOMS_ROOMS in order. Reaching a room's exit
-- loads the next room; the last exit changes to the ending state.
--
-- Seed puzzles: E / Enter / left click plants the selected seed on the
-- nearest fixed plot in range (Room:nearestPlot); Q / Tab or 1-3 select the
-- seed type; R resets the room. Crops grow on this state's own knife Timer
-- group, which is cleared whenever a room is loaded or reset, so nothing from
-- an earlier attempt keeps growing.
BackroomsState = Class{__includes = BaseState}

BackroomsState.usesPush = false

local function anyDown(keys)
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then return true end
    end
    return false
end

local function anyPressed(keys)
    for _, key in ipairs(keys) do
        if love.keyboard.wasPressed(key) then return true end
    end
    return false
end

-- gameData: the carried-over table from the farm (CarryOverGameData). Only
-- seeds are read; `rooms` overrides BACKROOMS_ROOMS (tests).
function BackroomsState:enter(gameData, rooms)
    self.gameData = gameData or CarryOverGameData(NewGameData())
    self.rooms = rooms or BACKROOMS_ROOMS
    self.timers = {}                     -- knife Timer group for crop growth
    self.message = nil                   -- {text, time left}
    print('[backrooms] seeds received: ' .. FormatSeeds(self.gameData.seeds))

    -- looping ambience (silent placeholder until sounds/backrooms_hum.ogg exists)
    local hum = gSounds['backrooms-hum']
    if hum then hum:setLooping(true); hum:play() end

    g3d.camera.resize(love.graphics.getDimensions())
    self:setMouseCaptured(true)
    self.finished = false
    self:loadRoom(1)
end

function BackroomsState:exit()
    Timer.clear(self.timers)
    local hum = gSounds['backrooms-hum']
    if hum then hum:stop() end
    self:setMouseCaptured(false)
end

-- Relative mouse mode hides and locks the cursor and reports deltas through
-- love.mousemoved, which main.lua forwards to BackroomsState:mousemoved.
function BackroomsState:setMouseCaptured(captured)
    self.mouseCaptured = captured
    if love.mouse.setRelativeMode then love.mouse.setRelativeMode(captured) end
end

-- Builds room `index` and places the player at its spawn. Seeds follow the
-- RoomStartingSeeds policy; the result is recorded for resetRoom.
function BackroomsState:loadRoom(index)
    local data = self.rooms[index]
    assert(data, 'no backrooms room ' .. tostring(index))
    Timer.clear(self.timers)
    self.roomIndex = index
    self.room = Room(data)
    self.gameData.seeds = RoomStartingSeeds(data, index, self.gameData.seeds)
    self.roomStartSeeds = CopySeeds(self.gameData.seeds)
    self.advancing = false
    self:selectSeed(self.selectedSeed)
    self:spawnPlayer()
    print(string.format('[backrooms] entered room %d/%d (%s), seeds: %s',
        index, #self.rooms, tostring(self.room.id), FormatSeeds(self.gameData.seeds)))
end

function BackroomsState:spawnPlayer()
    local s = self.room.spawn
    if self.player then
        self.player:setPosition(s[1], s[2], s[3])
    else
        self.player = PlayerController(s[1], s[2], s[3])
    end
    local ex, ey, ez = self.player:eyePosition()
    -- lookInDirection, not lookAt: g3d's lookAt derives yaw/pitch with a y-up
    -- formula that does not match lookInDirection/firstPersonLook (z-up)
    g3d.camera.lookInDirection(ex, ey, ez, s[4] or 0, 0)
end

-- Rebuilds the current room and restores the seeds recorded on entering it.
-- For Room 1 that is the topped-up farm seeds; for later rooms the fixed
-- allotment. Every crop is removed, pending growth is cancelled, demo crops
-- are rebuilt at their starting growth and the player returns to the spawn.
-- Bound to BACKROOMS_KEYS.reset.
function BackroomsState:resetRoom()
    Timer.clear(self.timers)
    self.room = Room(self.rooms[self.roomIndex])
    self.gameData.seeds = CopySeeds(self.roomStartSeeds)
    self.advancing = false
    self:selectSeed(self.selectedSeed)
    self:spawnPlayer()
    self:say('Room reset')
end

-- Seed selection --------------------------------------------------------------

-- Selects `seedType` if the player has one; otherwise the first type in
-- SEED_TYPES order that they do have; otherwise keeps `seedType` (or the
-- first type) so the HUD still shows a selection.
function BackroomsState:selectSeed(seedType)
    local seeds = self.gameData.seeds
    if seedType and (seeds[seedType] or 0) > 0 then
        self.selectedSeed = seedType
        return
    end
    for _, t in ipairs(SEED_TYPES) do
        if (seeds[t] or 0) > 0 then self.selectedSeed = t; return end
    end
    self.selectedSeed = seedType or SEED_TYPES[1]
end

-- Next type (in SEED_TYPES order, wrapping) that the player holds.
function BackroomsState:cycleSeed()
    local start = 1
    for i, t in ipairs(SEED_TYPES) do if t == self.selectedSeed then start = i end end
    for k = 1, #SEED_TYPES do
        local t = SEED_TYPES[(start + k - 1) % #SEED_TYPES + 1]
        if (self.gameData.seeds[t] or 0) > 0 then self.selectedSeed = t; return end
    end
end

function BackroomsState:say(text)
    self.message = {text = text, time = 2.5}
end

-- Planting --------------------------------------------------------------------

-- The plot the player could plant on right now, or nil.
function BackroomsState:targetPlot()
    return self.room:nearestPlot(self.player.x, self.player.y, self.player.z)
end

local PLANT_MESSAGES = {
    ['no-plot'] = 'Seeds only take on the soil plots',
    ['no-seeds'] = 'No %s seeds left',
    ['occupied'] = 'Something is already growing here',
    ['growing'] = 'Something is already growing here',
    ['wrong-seed'] = 'This %s needs a %s seed',
}

-- Plants the selected seed on the nearest plot. Returns ok, crop-or-reason.
function BackroomsState:plant()
    local plot = self:targetPlot()
    local seedType = self.selectedSeed
    local ok, result = self.room:plant(plot, seedType, self.gameData.seeds, self.timers)
    if ok then
        gSounds['plant']:play()
        self:say(result.demo and ('The ' .. seedType .. ' keeps growing...') or ('Planted a ' .. seedType))
        print(string.format('[backrooms] planted %s on plot %s, seeds: %s',
            seedType, plot.id, FormatSeeds(self.gameData.seeds)))
        if (self.gameData.seeds[seedType] or 0) == 0 then self:selectSeed(seedType) end
    else
        gSounds['deny']:play()
        local fmt = PLANT_MESSAGES[result] or result
        if result == 'wrong-seed' then
            self:say(string.format(fmt, plot.crop.type, plot.crop.type))
        else
            self:say(string.format(fmt, seedType))
        end
    end
    return ok, result
end

-- The current room is done: load the next one, or show the ending.
function BackroomsState:advance()
    if self.advancing or self.finished then return end
    self.advancing = true
    if self.roomIndex < #self.rooms then
        self:loadRoom(self.roomIndex + 1)
    else
        self.finished = true
        gStateMachine:change('ending', self.gameData)
    end
end

function BackroomsState:mousemoved(x, y, dx, dy)
    if self.mouseCaptured then
        g3d.camera.firstPersonLook(dx, dy)
    end
end

function BackroomsState:movementInput()
    local f, s = 0, 0
    if anyDown(BACKROOMS_KEYS.forward) then f = f + 1 end
    if anyDown(BACKROOMS_KEYS.back) then f = f - 1 end
    if anyDown(BACKROOMS_KEYS.right) then s = s + 1 end
    if anyDown(BACKROOMS_KEYS.left) then s = s - 1 end
    return {forward = f, strafe = s}
end

function BackroomsState:update(dt)
    if IsDebugAdvancePressed() then
        self:advance()
        return
    end

    local clickPlants = false
    if self.mouseCaptured and anyPressed(BACKROOMS_KEYS.releaseMouse) then
        self:setMouseCaptured(false)
    elseif not self.mouseCaptured and love.mouse.wasPressed(1) then
        self:setMouseCaptured(true)
    elseif self.mouseCaptured and love.mouse.wasPressed(1) then
        clickPlants = true
    end

    if anyPressed(BACKROOMS_KEYS.reset) then
        self:resetRoom()
        return
    end
    for i, key in ipairs(BACKROOMS_KEYS.seedSlots) do
        if love.keyboard.wasPressed(key) and SEED_TYPES[i] then self.selectedSeed = SEED_TYPES[i] end
    end
    if anyPressed(BACKROOMS_KEYS.nextSeed) then self:cycleSeed() end
    if clickPlants or anyPressed(BACKROOMS_KEYS.plant) then self:plant() end

    if self.message then
        self.message.time = self.message.time - dt
        if self.message.time <= 0 then self.message = nil end
    end

    -- growth, then crops that finished growing take effect (once the player
    -- is clear of them), then the player moves against this frame's world
    Timer.update(dt, self.timers)
    local bmin, bmax = self.player:bounds()
    self.room:updateCrops(bmin, bmax)

    local direction = g3d.camera.getDirectionPitch()
    self.player:update(dt, self:movementInput(), direction, self.room:solidColliders(), self.room:climbVolumes())

    if self.player.z < self.room.killZ then
        self:spawnPlayer()
    end

    local ex, ey, ez = self.player:eyePosition()
    g3d.camera.lookInDirection(ex, ey, ez)

    local pmin, pmax = self.player:bounds()
    if self.room:overlapsExit(pmin, pmax) then
        self:advance()
    end
end

function BackroomsState:render()
    self.room:draw(self.player.x, self.player.y)
end

function BackroomsState:renderHUD()
    local w, h = love.graphics.getDimensions()
    -- translucent bands keep the white HUD text readable on the pale walls
    -- (top: room name + seeds; bottom: up to two hint lines + debug line)
    local bandLineH = gFonts['default']:getHeight() + 4
    local bottomTop = h - 52 - bandLineH - 6
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle('fill', 0, 0, w, 32 + bandLineH + 4)
    love.graphics.rectangle('fill', 0, bottomTop, w, h - bottomTop)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.print(string.format('%s  (%d/%d)', self.room.name, self.roomIndex, #self.rooms), 10, 10)

    -- per-type seed counts; the selected type is bracketed and bright
    local x = 10
    for i, t in ipairs(SEED_TYPES) do
        local selected = t == self.selectedSeed
        local n = self.gameData.seeds[t] or 0
        local label = string.format(selected and '[%d %s x%d]' or ' %d %s x%d ', i, t, n)
        if selected then love.graphics.setColor(1, 1, 0.4, 1)
        elseif n == 0 then love.graphics.setColor(0.6, 0.6, 0.6, 1)
        else love.graphics.setColor(1, 1, 1, 1) end
        love.graphics.print(label, x, 32)
        x = x + gFonts['default']:getWidth(label) + 12
    end
    love.graphics.setColor(1, 1, 1, 1)

    local plot = self:targetPlot()
    if plot then
        local ok, reason = self.room:canPlant(plot, self.selectedSeed, self.gameData.seeds)
        local prompt
        if ok then prompt = 'E / click: plant ' .. self.selectedSeed
        elseif reason == 'wrong-seed' then prompt = 'This ' .. plot.crop.type .. ' needs a ' .. plot.crop.type .. ' seed'
        elseif reason == 'no-seeds' then prompt = 'No ' .. self.selectedSeed .. ' seeds (Q: switch)'
        else prompt = 'Plot in use' end
        love.graphics.printf(prompt, 0, h / 2 + 24, w, 'center')
    end
    if self.message then
        love.graphics.printf(self.message.text, 0, h / 2 + 48, w, 'center')
    end

    -- crosshair
    love.graphics.line(w / 2 - 6, h / 2, w / 2 + 6, h / 2)
    love.graphics.line(w / 2, h / 2 - 6, w / 2, h / 2 + 6)

    -- the controls hint is split over two lines when one would not fit
    -- (e.g. a 640 px wide window), instead of letting printf wrap mid-phrase
    local font = gFonts['default']
    local hints = self.mouseCaptured
        and {'WASD: move   mouse: look   E: plant   Q / 1-3: seed', 'R: reset room   Esc: free mouse'}
        or {'Click to capture the mouse'}
    local joined = table.concat(hints, '   ')
    if font:getWidth(joined) <= w - 20 then hints = {joined} end
    local lineH = font:getHeight() + 4
    for i, line in ipairs(hints) do
        love.graphics.printf(line, 0, h - 52 - (#hints - i) * lineH, w, 'center')
    end
    if DEBUG_MODE then
        love.graphics.print(DEBUG_ADVANCE_KEY .. ': debug skip room   fps: ' .. love.timer.getFPS(), 10, h - 26)
    end
end
