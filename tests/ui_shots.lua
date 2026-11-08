-- UI screenshots (title, hotbar bright/dark, ending early/with buttons). Dev only:
--   UI_OUT=/workspace/qa/ui xvfb-run -a -s '-screen 0 1024x1024x24' love . --ui-shots
local OUT = os.getenv('UI_OUT') or '/tmp/ui-shots'
os.execute('mkdir -p "' .. OUT .. '"')
BACKROOMS_RUN_SEED = 4242
local DT = 1 / 60

local function step(n)
    for _ = 1, n do
        love.timer.step()
        love.update(DT)
        love.graphics.origin()
        love.graphics.clear(love.graphics.getBackgroundColor())
        love.draw()
        love.graphics.present()
    end
end
local function shot(name)
    local done = false
    love.graphics.origin()
    love.graphics.clear(love.graphics.getBackgroundColor())
    love.draw()
    love.graphics.captureScreenshot(function(data)
        local f = io.open(OUT .. '/' .. name .. '.png', 'wb')
        f:write(data:encode('png'):getString()); f:close(); done = true
    end)
    love.graphics.present()
    for _ = 1, 5 do if done then break end; step(1) end
    print('shot ' .. name .. (done and '' or ' FAILED'))
end
local function backrooms(preset)
    gStateMachine:change('backrooms', CarryOverGameData(NewGameData()))
    local s = gStateMachine.current
    s.gameData.seeds = {beanstalk = 3, pumpkin = 0, vine = 1}
    s:selectSeed('beanstalk')
    s.hintTime = 0
    s.room:setLighting(preset)
    step(30)
    return s
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    love.timer.step()
    love.window.updateMode(1024, 768, {vsync = 0})
    love.resize(1024, 768)
    step(5); gStateMachine:change('start'); step(60); shot('title')
    backrooms('bright'); shot('hotbar-bright')
    backrooms('near-dark'); shot('hotbar-dark')
    gStateMachine:change('ending', {gameData = NewGameData(), runSeed = 4242})
    step(30); shot('ending-early')
    step(60 * 6); shot('ending-buttons')
    return function() return 0 end
end
