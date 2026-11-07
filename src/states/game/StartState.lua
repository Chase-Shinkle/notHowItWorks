StartState = Class{__includes = BaseState}

function StartState:render()
    love.graphics.setFont(gFonts['default'])
    love.graphics.printf('Game Jam', 0, VIRTUAL_HEIGHT / 2 - 8, VIRTUAL_WIDTH, 'center')
end
