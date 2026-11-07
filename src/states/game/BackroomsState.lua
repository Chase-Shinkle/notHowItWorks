-- 3D backrooms. Opts out of push: g3d draws straight to the screen at native
-- resolution with the window's depth buffer, then renderHUD draws 2D on top
-- with depth testing disabled (see love.draw in main.lua).
--
-- The player walks through BACKROOMS_ROOMS in order. Reaching a room's exit
-- loads the next room; the last exit changes to the ending state.
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
    print('[backrooms] seeds received: ' .. FormatSeeds(self.gameData.seeds))

    g3d.camera.resize(love.graphics.getDimensions())
    self:setMouseCaptured(true)
    self.finished = false
    self:loadRoom(1)
end

function BackroomsState:exit()
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
    self.roomIndex = index
    self.room = Room(data)
    self.gameData.seeds = RoomStartingSeeds(data, index, self.gameData.seeds)
    self.roomStartSeeds = CopySeeds(self.gameData.seeds)
    self.advancing = false
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
-- allotment. Crops/plots are added in section 5 (task 5.5 binds a key).
function BackroomsState:resetRoom()
    self.room = Room(self.rooms[self.roomIndex])
    self.gameData.seeds = CopySeeds(self.roomStartSeeds)
    self.advancing = false
    self:spawnPlayer()
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

    if self.mouseCaptured and anyPressed(BACKROOMS_KEYS.releaseMouse) then
        self:setMouseCaptured(false)
    elseif not self.mouseCaptured and love.mouse.wasPressed(1) then
        self:setMouseCaptured(true)
    end

    local direction = g3d.camera.getDirectionPitch()
    self.player:update(dt, self:movementInput(), direction, self.room.colliders)

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
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.print(string.format('%s  (%d/%d)', self.room.name, self.roomIndex, #self.rooms), 10, 10)
    love.graphics.print('seeds: ' .. FormatSeeds(self.gameData.seeds), 10, 32)

    -- crosshair
    love.graphics.line(w / 2 - 6, h / 2, w / 2 + 6, h / 2)
    love.graphics.line(w / 2, h / 2 - 6, w / 2, h / 2 + 6)

    local hint = self.mouseCaptured and 'WASD / arrows: move   mouse: look   Esc: free mouse'
        or 'Click to capture the mouse'
    love.graphics.printf(hint, 0, h - 52, w, 'center')
    if DEBUG_MODE then
        love.graphics.print(DEBUG_ADVANCE_KEY .. ': debug skip room   fps: ' .. love.timer.getFPS(), 10, h - 26)
    end
end
