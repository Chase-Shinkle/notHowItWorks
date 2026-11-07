StartState = Class{__includes = BaseState}

function StartState:update(dt)
    if love.keyboard.wasPressed('return') or love.keyboard.wasPressed('kpenter')
        or love.keyboard.wasPressed('space') or IsDebugAdvancePressed() then
        gStateMachine:change('farm', NewGameData())
    end
end

function StartState:render()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.printf('Game Jam', 0, VIRTUAL_HEIGHT / 2 - 8, VIRTUAL_WIDTH, 'center')
    love.graphics.setFont(gFonts['small'])
    love.graphics.printf('Press Enter', 0, VIRTUAL_HEIGHT / 2 + 16, VIRTUAL_WIDTH, 'center')
end
