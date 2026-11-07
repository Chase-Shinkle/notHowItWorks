-- Ending screen, shown after the last backrooms exit. Renders through push
-- like the start screen. Enter/Space (or the debug key) returns to the start.
EndingState = Class{__includes = BaseState}

function EndingState:enter(gameData)
    self.gameData = gameData or NewGameData()
    self.time = 0
    print('[ending] escaped the backrooms with seeds: ' .. FormatSeeds(self.gameData.seeds))
end

function EndingState:update(dt)
    self.time = self.time + dt
    -- a short delay so a key held while reaching the exit doesn't skip it
    if self.time > 0.5 and (love.keyboard.wasPressed('return') or love.keyboard.wasPressed('kpenter')
        or love.keyboard.wasPressed('space')) or IsDebugAdvancePressed() then
        gStateMachine:change('start')
    end
end

function EndingState:render()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(gFonts['default'])
    love.graphics.printf('You found a way out.', 0, VIRTUAL_HEIGHT / 2 - 24, VIRTUAL_WIDTH, 'center')
    love.graphics.setFont(gFonts['small'])
    love.graphics.printf("I don't think it's supposed to work like that.", 0, VIRTUAL_HEIGHT / 2 + 4, VIRTUAL_WIDTH, 'center')
    love.graphics.printf('Press Enter', 0, VIRTUAL_HEIGHT / 2 + 28, VIRTUAL_WIDTH, 'center')
end
