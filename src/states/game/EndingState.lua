-- Ending screen, shown after the last backrooms exit: a live 3D backrooms
-- hallway (generated from the run seed) under a scripted camera, with the
-- headline, subtitle and a Back to Title / Exit Game menu fading in.
-- Native-resolution path (usesPush = false), like the backrooms.
EndingState = Class{__includes = BaseState}
EndingState.usesPush = false

local KEYS = {'up', 'down', 'w', 's', 'return', 'kpenter', 'space'}

-- Authored fallback: a plain 4 m wide, 30 m long hallway along +x.
local function authoredHall()
    local T, H, L, W = 0.2, 3, 30, 4
    return {
        id = 'ending-hall', name = 'Ending hall', spawn = {2, 0, 0, 0}, lighting = ENDING_LIGHTING,
        boxes = {
            {kind = 'floor', pos = {L / 2, 0, -T / 2}, size = {L, W, T}},
            {kind = 'ceiling', pos = {L / 2, 0, H + T / 2}, size = {L, W + 2 * T, T}},
            {kind = 'wall', pos = {L / 2, W / 2 + T / 2, H / 2}, size = {L, T, H}},
            {kind = 'wall', pos = {L / 2, -W / 2 - T / 2, H / 2}, size = {L, T, H}},
            {kind = 'wall', pos = {L + T / 2, 0, H / 2}, size = {T, W + 2 * T, H}},
            {kind = 'wall', pos = {-T / 2, 0, H / 2}, size = {T, W + 2 * T, H}},
        },
        exit = {pos = {L - 1, 0, 1.1}, size = {0.6, 1.4, 2.2}},
        allotment = {},
    }, {{2, 0}, {26, 0}}
end

-- Room data and camera waypoints ({x, y} list) for a run seed. Deterministic.
-- Walks the leading flat, module-free cells of the generated path; if no
-- candidate has at least two, uses the authored hallway.
function EndingState.buildHallway(runSeed)
    for k = 0, ENDING_LEVEL_TRIES - 1 do
        local seed = LevelGen.levelSeed(runSeed, ENDING_LEVEL_INDEX + k)
        local ok, data = pcall(LevelGen.generate, seed, 1, {name = 'Ending hallway'})
        if ok and data and data.meta and data.meta.cells and data.meta.path then
            local byKey = {}
            for _, c in ipairs(data.meta.cells) do byKey[c.cx .. ',' .. c.cy] = c end
            local pts = {}
            for _, p in ipairs(data.meta.path) do
                local c = byKey[p[1] .. ',' .. p[2]]
                if not c or c.kind == 'module' or c.region ~= 0 or #pts >= ENDING_PATH_CELLS then break end
                local x, y = LevelGen.cellCenter(p[1], p[2])
                pts[#pts + 1] = {x, y}
            end
            if #pts >= 2 then
                data.pickups, data.plots, data.lighting = {}, {}, ENDING_LIGHTING
                return data, pts
            end
        end
    end
    return authoredHall()
end

-- Camera pose at time t along waypoints: x, y, z, yaw, pitch. Pure; holds at the
-- end of the path. Sway is sideways of the path and small enough to stay in the cell.
function EndingState.cameraAt(pts, t)
    local lens, total = {}, 0
    for i = 1, #pts - 1 do
        lens[i] = math.sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2)
        total = total + lens[i]
    end
    local function at(s)
        s = math.max(0, math.min(total, s))
        for i = 1, #lens do
            if s <= lens[i] or i == #lens then
                local f = lens[i] > 0 and math.min(1, s / lens[i]) or 0
                local a, b = pts[i], pts[i + 1]
                return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, i
            end
            s = s - lens[i]
        end
    end
    local s = t * ENDING_CAM_SPEED
    local x, y, seg = at(s)
    local ax, ay = at(s + ENDING_CAM_LOOKAHEAD)
    local dx, dy = ax - x, ay - y
    if dx * dx + dy * dy < 0.01 then
        local a, b = pts[#pts - 1], pts[#pts]
        dx, dy = b[1] - a[1], b[2] - a[2]
    end
    local yaw = math.atan2(dy, dx)
    local n = math.sqrt(dx * dx + dy * dy)
    local side = math.sin(t * 0.55) * ENDING_CAM_SWAY
    x, y = x - dy / n * side, y + dx / n * side
    return x, y, BACKROOMS_EYE_HEIGHT + math.sin(t * 0.9) * 0.02,
        yaw + math.sin(t * 0.4) * 0.05, math.sin(t * 0.7) * 0.015
end

-- gameData: the carried-over table, or {gameData = ..., runSeed = ...}.
function EndingState:enter(param)
    local gameData, runSeed
    if type(param) == 'table' and (param.gameData or param.runSeed) then
        gameData, runSeed = param.gameData, param.runSeed
    else
        gameData = param
    end
    self.gameData = gameData or NewGameData()
    self.runSeed = runSeed or math.random(1, 999999)
    self.time = 0
    print('[ending] escaped the backrooms with seeds: ' .. FormatSeeds(self.gameData.seeds)
        .. ', run seed ' .. self.runSeed)

    local data
    data, self.path = EndingState.buildHallway(self.runSeed)
    self.room = Room(data)
    g3d.camera.resize(love.graphics.getDimensions())
    self:poseCamera()

    if self.audio then self.audio:dispose() end
    self.audio = BackroomsAudio.new()
    local song = gSounds['ending-music']
    if song then song:stop(); song:setLooping(false); song:setVolume(ENDING_MUSIC_VOLUME); song:play() end
    if love.mouse.setRelativeMode then love.mouse.setRelativeMode(false) end
    if love.mouse.setVisible then love.mouse.setVisible(true) end

    self.menu = UI.Menu.new({
        {label = 'Back to Title', onActivate = function() gStateMachine:change('start') end},
        {label = 'Exit Game', onActivate = function() love.event.quit() end},
    })
    self:layoutMenu()
end

function EndingState:layoutMenu()
    local w, h = love.graphics.getDimensions()
    self.menu:layout(w / 2, h * 0.6, math.min(w * 0.6, h * 0.5), h * 0.09, h * 0.025)
end

function EndingState:exit()
    local song = gSounds['ending-music']
    if song then song:stop() end
    if self.audio then self.audio:dispose(); self.audio = nil end
end

function EndingState:poseCamera()
    local x, y, z, yaw, pitch = EndingState.cameraAt(self.path, self.time)
    self.camX, self.camY, self.camZ = x, y, z
    g3d.camera.lookInDirection(x, y, z, yaw, pitch)
end

-- Fade 0..1 of an element that starts at `at`.
local function fade(t, at) return math.max(0, math.min(1, (t - at) / ENDING_FADE)) end

function EndingState:buttonsReady()
    return self.time >= ENDING_BUTTONS_AT + ENDING_FADE
end

function EndingState:update(dt)
    self.time = self.time + dt
    self:poseCamera()
    if self.audio then self.audio:update(dt, nil) end
    -- input only counts once the buttons are fully shown, so a key held from
    -- the final exit (or pressed during the reveal) activates nothing
    if IsDebugAdvancePressed() then return gStateMachine:change('start') end   -- dev key
    if not self:buttonsReady() then return end
    do
        local mx, my = love.mouse.getPosition()
        if mx ~= self.lastMX or my ~= self.lastMY then
            self.lastMX, self.lastMY = mx, my
            self.menu:mousemoved(mx, my)
        end
        if love.mouse.wasPressed(1) and self.menu:mousepressed(mx, my, 1) then return end
    end
    for _, k in ipairs(KEYS) do
        if love.keyboard.wasPressed(k) then
            if self.menu:keypressed(k) then return end
        end
    end
end

function EndingState:render()
    BackroomsLook.renderScene(function() self.room:draw(self.camX, self.camY) end)
end

function EndingState:renderHUD()
    local g = love.graphics
    local w, h = g.getDimensions()
    -- soft dark band behind the text keeps it readable on pale walls
    local bandA = 0.45 * fade(self.time, ENDING_HEADLINE_AT)
    g.setColor(0, 0, 0, bandA)
    g.rectangle('fill', 0, h * 0.22, w, h * 0.3)

    local head, sub = UI.font(UI.scaledSize(0.09, h)), UI.font(UI.scaledSize(0.035, h))
    local a = fade(self.time, ENDING_HEADLINE_AT)
    g.setFont(head)
    g.setColor(1, 0.96, 0.8, a)
    g.printf('You found a way out.', 0, h * 0.26, w, 'center')
    a = fade(self.time, ENDING_SUBTITLE_AT)
    g.setFont(sub)
    g.setColor(1, 1, 1, a)
    g.printf("I don't think it's supposed to work like that.", 0, h * 0.40, w, 'center')

    self:layoutMenu()
    local ba = fade(self.time, ENDING_BUTTONS_AT)
    if ba > 0 then self.menu:draw(UI.font(UI.scaledSize(0.05, h)), ba) end
    g.setColor(1, 1, 1, 1)
end
