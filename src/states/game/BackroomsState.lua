-- 3D backrooms (stub). Opts out of push: g3d draws straight to the screen at
-- native resolution with the window's depth buffer, then renderHUD draws 2D
-- on top with depth testing disabled (see love.draw in main.lua).
BackroomsState = Class{__includes = BaseState}

BackroomsState.usesPush = false

function BackroomsState:enter(gameData)
    self.gameData = gameData or NewGameData()
    print('[backrooms] seeds received: ' .. FormatSeeds(self.gameData.seeds))

    -- two interpenetrating cubes over a floor slab: if depth testing works the
    -- cubes cut cleanly through each other along their intersection
    self.cube = g3d.newModel(NewBoxVerts(1, 1, 1), gTextures['wall'], {0, 0, 0.5})
    self.crossCube = g3d.newModel(NewBoxVerts(1.6, 0.4, 0.4), gTextures['wall'], {0, 0, 0.5})
    self.floor = g3d.newModel(NewBoxVerts(8, 8, 0.1), gTextures['floor'], {0, 0, -0.05})
    self.angle = 0

    g3d.camera.resize(love.graphics.getDimensions())
    g3d.camera.lookAt(-3, -1.5, 1.8, 0, 0, 0.4)
end

function BackroomsState:update(dt)
    self.angle = self.angle + dt * 0.8
    self.cube:setRotation(0, 0, self.angle)
    self.crossCube:setRotation(0, 0, -self.angle * 1.5)

    if IsDebugAdvancePressed() then
        gStateMachine:change('start')
    end
end

function BackroomsState:render()
    love.graphics.setColor(0.85, 0.8, 0.45, 1)
    self.floor:draw()
    love.graphics.setColor(0.95, 0.9, 0.55, 1)
    self.cube:draw()
    love.graphics.setColor(0.55, 0.75, 0.35, 1)
    self.crossCube:draw()
    love.graphics.setColor(1, 1, 1, 1)
end

function BackroomsState:renderHUD()
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.print('BACKROOMS (stub) - native ' .. w .. 'x' .. h, 10, 10)
    love.graphics.print('seeds: ' .. FormatSeeds(self.gameData.seeds), 10, 32)
    if DEBUG_MODE then
        love.graphics.print(DEBUG_ADVANCE_KEY .. ': debug -> start   fps: ' .. love.timer.getFPS(), 10, h - 26)
    end
end
