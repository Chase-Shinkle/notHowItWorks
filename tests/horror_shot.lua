-- dev harness: love . --horror-shot ; BR_MODE=vhs|vignette
local state, frames = nil, 0
local origUpdate, origDraw = love.update, love.draw
local mode = os.getenv('BR_MODE') or 'vhs'
local taken = false
function love.update(dt)
    frames = frames + 1
    if frames == 1 then gStateMachine:change('backrooms'); state = gStateMachine.current end
    origUpdate(1 / 60)
    if mode == 'vignette' and frames > 5 then BackroomsLook.idleVignette = 1 end
    BackroomsLook.timeOverride = 12.37
    if frames > 120 then love.event.quit() end
end
function love.draw()
    origDraw()
    if frames == 100 and not taken then taken = true
        love.graphics.captureScreenshot(function(d) d:encode('png','tmpshot.png')
            local fh = io.open('/workspace/qa/horror/'..(mode=='vhs' and 'vhs' or 'vignette')..'.png','wb'); fh:write(love.filesystem.read('tmpshot.png')); fh:close(); love.event.quit() end)
    end
end
