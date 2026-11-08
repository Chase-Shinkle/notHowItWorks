StartState = Class{__includes = BaseState}

local TITLE = 'Back to Farming'
local TILE = FARM_TILE
local BUTTON_W, BUTTON_H, BUTTON_GAP, BUTTON_Y = 120, 24, 8, 206
local MENU_KEYS = {'up', 'down', 'w', 's', 'return', 'kpenter', 'space'}
-- soil plots: {col, row, seedType, stage}, pixel positions on the 320x320 canvas
local PLOTS = {
    {1, 4, 'beanstalk', 3}, {2, 4, 'pumpkin', 4}, {3, 4, 'vine', 2},
    {1, 5, 'pumpkin', 2}, {2, 5, 'vine', 4}, {3, 5, 'beanstalk', 4},
}
local CLOUDS = {{y = 14, speed = 6, x0 = 20, w = 46}, {y = 78, speed = 4, x0 = 200, w = 34}, {y = 40, speed = 8, x0 = 120, w = 28}}

-- Raw window coordinates -> virtual canvas; off-canvas points map far away.
local function toVirtual(x, y)
    local gx, gy = push:toGame(x, y)
    if not gx then return -1000, -1000 end
    return gx, gy
end

function StartState:enter()
    -- the farm theme starts here and keeps playing into the farm (FarmState:enter doesn't restart it)
    local music = gSounds['farm-music']
    if music then
        music:setLooping(true)
        if not music:isPlaying() then music:play() end
    end
    self.time = 0
    self.menu = UI.Menu.new({
        {label = 'Play Game', onActivate = function() gStateMachine:change('farm', NewGameData()) end},
        {label = 'Exit Game', onActivate = function() love.event.quit() end},
    }, {mapper = toVirtual})
    self.menu:layout(VIRTUAL_WIDTH / 2, BUTTON_Y, BUTTON_W, BUTTON_H, BUTTON_GAP)
end

function StartState:update(dt)
    self.time = self.time + dt
    local mx, my = love.mouse.getPosition()
    if self.lastMouseX ~= mx or self.lastMouseY ~= my then
        self.menu:mousemoved(mx, my)
        self.lastMouseX, self.lastMouseY = mx, my
    end
    if love.mouse.wasPressed(1) then self.menu:mousepressed(mx, my, 1) end
    if IsDebugAdvancePressed() then self.menu:activate(1) end
    for _, key in ipairs(MENU_KEYS) do
        if love.keyboard.wasPressed(key) then self.menu:keypressed(key) end
    end
end

local function tiled(image, x, y)
    local w, h = image:getDimensions()
    love.graphics.draw(image, x, y, 0, TILE / w, TILE / h)
end

local function sprite(image, x, y, scale, kx)
    local w, h = image:getDimensions()
    love.graphics.draw(image, x, y, 0, scale, scale, w / 2, h, kx or 0, 0)
end

function StartState:renderScene()
    local t = self.time
    love.graphics.setColor(1, 1, 1, 1)
    for row = 0, VIRTUAL_HEIGHT / TILE - 1 do
        for col = 0, VIRTUAL_WIDTH / TILE - 1 do tiled(gTextures['grass'], col * TILE, row * TILE) end
    end
    -- dirt path running down from the plots to the bottom edge
    love.graphics.setColor(1, 0.94, 0.82, 1)
    for row = 5, VIRTUAL_HEIGHT / TILE - 1 do tiled(gTextures['path'], 5 * TILE, row * TILE) end
    -- soil plots with swaying crops
    for _, p in ipairs(PLOTS) do
        local x, y = (p[1] - 1) * TILE + 16, (p[2] - 1) * TILE + 12
        love.graphics.setColor(1, 1, 1, 1)
        tiled(gTextures['soil'], x, y)
        tiled(gTextures['plot'], x, y)
        love.graphics.setColor(0, 0, 0, 0.22)
        love.graphics.ellipse('fill', x + TILE / 2, y + TILE - 3, 8, 3)
        love.graphics.setColor(1, 1, 1, 1)
        local img = gTextures['crop-' .. p[3] .. '-' .. p[4]]
        local w, h = img:getDimensions()
        sprite(img, x + TILE / 2, y + TILE - 2, math.min(2, (TILE - 4) / math.max(w, h)),
            math.sin(t * FARM_SWAY_SPEED + p[1] * 1.3 + p[2]) * FARM_SWAY_SKEW)
    end
    -- fence closing the plot block on the right
    local fence = gTextures['fence']
    local fw, fh = fence:getDimensions()
    for row = 3, 4 do
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(fence, 4 * TILE + 16 - fw, row * TILE + 12, 0, 2, TILE / fh)
    end
    -- barn, right of the path
    local barn = gTextures['barn']
    local bw, bh = barn:getDimensions()
    local bx, by = VIRTUAL_WIDTH - 96 - 4, 6 * TILE - 8
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse('fill', bx + 48, by - 3, 44, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(barn, bx, by - 96, 0, 96 / bw, 96 / bh)
    -- bushes
    for i, p in ipairs({{3 * TILE + 8, 8 * TILE}, {9 * TILE, 8 * TILE + 14}}) do
        love.graphics.setColor(1, 1, 1, 1)
        sprite(gTextures[i % 2 == 0 and 'bush-2' or 'bush-1'], p[1], p[2], 1, math.sin(t * FARM_SWAY_SPEED + i * 2.1) * FARM_SWAY_SKEW)
    end
    -- drifting clouds (wrap around the screen)
    for _, c in ipairs(CLOUDS) do
        local x = (c.x0 + t * c.speed) % (VIRTUAL_WIDTH + c.w * 2) - c.w
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.ellipse('fill', x, c.y, c.w / 2, c.w / 6)
        love.graphics.ellipse('fill', x - c.w / 5, c.y - c.w / 8, c.w / 4, c.w / 6)
        love.graphics.ellipse('fill', x + c.w / 5, c.y - c.w / 10, c.w / 4, c.w / 7)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function StartState:render()
    self:renderScene()
    local font = gFonts['title-48']
    local maxW = VIRTUAL_WIDTH * 0.9
    local s = UI.fitScale(font, TITLE, maxW)
    local tw = font:getWidth(TITLE) * s
    local x, y = math.floor((VIRTUAL_WIDTH - tw) / 2), 56
    love.graphics.setFont(font)
    love.graphics.setColor(0.1, 0.07, 0.03, 0.8)
    love.graphics.print(TITLE, x + 2, y + 2, 0, s, s)
    love.graphics.setColor(1, 0.93, 0.6, 1)
    love.graphics.print(TITLE, x, y, 0, s, s)
    love.graphics.setColor(1, 1, 1, 1)
    self.menu:draw(gFonts['title-32'])
end
