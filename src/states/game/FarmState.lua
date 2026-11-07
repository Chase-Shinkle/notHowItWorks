-- 2D farm (stub). Renders through push at the virtual resolution.
FarmState = Class{__includes = BaseState}

FarmState.usesPush = true

function FarmState:enter(gameData)
    self.gameData = gameData or NewGameData()
end

function FarmState:update(dt)
    if IsDebugAdvancePressed() then
        gStateMachine:change('backrooms', self.gameData)
    end
end

function FarmState:render()
    -- tile the grass texture (or its flat-color placeholder) as a backdrop
    local grass = gTextures['grass']
    local tw, th = grass:getDimensions()
    local sx, sy = 16 / tw, 16 / th
    love.graphics.setColor(1, 1, 1, 1)
    for y = 0, VIRTUAL_HEIGHT - 1, 16 do
        for x = 0, VIRTUAL_WIDTH - 1, 16 do
            love.graphics.draw(grass, x, y, 0, sx, sy)
        end
    end

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle('fill', 0, 0, VIRTUAL_WIDTH, 44)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.printf('FARM (stub)', 0, 4, VIRTUAL_WIDTH, 'center')
    love.graphics.setFont(gFonts['small'])
    love.graphics.printf('seeds: ' .. FormatSeeds(self.gameData.seeds), 0, 24, VIRTUAL_WIDTH, 'center')
    if DEBUG_MODE then
        love.graphics.printf(DEBUG_ADVANCE_KEY .. ': debug -> backrooms', 0, VIRTUAL_HEIGHT - 14, VIRTUAL_WIDTH, 'center')
    end
end
