-- Dev-only: `love . --fall-shot --run-seed=2026` with BR_OUT=<file.png>.
-- Enters the real backrooms state, drops the player below killZ, and captures
-- one real frame mid-fade (~0.35s into the fade-out), then quits.
local state, frames, shot = nil, 0, false
local origUpdate, origDraw = love.update, love.draw
function love.update(dt)
    frames = frames + 1
    if frames == 1 then gStateMachine:change('backrooms'); state = gStateMachine.current end
    if frames == 5 and state.player then state.player:setPosition(state.player.x, state.player.y, state.room.killZ - 0.5) end
    origUpdate(1 / 60)
    if state.fall and state.fall.t >= 0.35 and not shot then shot = 'pending' end
    if frames > 600 then love.event.quit() end
end
function love.draw()
    origDraw()
    if shot == 'pending' then
        shot = 'taken'
        print('[fall-shot] alpha=' .. state.fall.alpha .. ' phase=' .. state.fall.phase)
        love.graphics.captureScreenshot(function(d)
            d:encode('png', 'tmpshot.png')
            local out = os.getenv('BR_OUT') or '/workspace/qa/fall/mid-fade.png'
            local f = love.filesystem.read('tmpshot.png')
            local fh = io.open(out, 'wb'); fh:write(f); fh:close()
            print('[fall-shot] saved ' .. out); love.event.quit()
        end)
    end
end
