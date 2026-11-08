-- Nearest-neighbour by default, before any asset exists: src/Dependencies
-- loads every image and font at require time, so setting the default later
-- (e.g. in love.load) would leave them all linear and blurry. The large
-- backrooms surface textures opt back into linear in src/Dependencies.lua.
love.graphics.setDefaultFilter('nearest', 'nearest')

require 'src/Dependencies'

function love.load()
    math.randomseed(os.time())
    love.window.setTitle('Back to Farming')

    push:setupScreen(VIRTUAL_WIDTH, VIRTUAL_HEIGHT, WINDOW_WIDTH, WINDOW_HEIGHT, {
        vsync = true,
        fullscreen = false,
        resizable = true
    })

    gStateMachine = StateMachine({
        ['start'] = function() return StartState() end,
        ['farm'] = function() return FarmState() end,
        ['backrooms'] = function() return BackroomsState() end,
        ['ending'] = function() return EndingState() end,
    })
    g3d.camera.resize(love.graphics.getDimensions())
    gStateMachine:change('start')

    love.keyboard.keysPressed = {}
    love.mouse.buttonsPressed = {}
end

function love.resize(w, h)
    push:resize(w, h)
    g3d.camera.resize(w, h)
end

function love.keypressed(key)
    love.keyboard.keysPressed[key] = true
end

function love.keyboard.wasPressed(key)
    return love.keyboard.keysPressed[key] or false
end

function IsDebugAdvancePressed()
    return DEBUG_MODE and love.keyboard.wasPressed(DEBUG_ADVANCE_KEY)
end

-- Needed for g3d.camera.firstPersonLook(dx, dy) if you use a first-person camera
function love.mousemoved(x, y, dx, dy)
    if gStateMachine and gStateMachine.current and gStateMachine.current.mousemoved then
        gStateMachine.current:mousemoved(x, y, dx, dy)
    end
end

function love.mousepressed(x, y, button)
    love.mouse.buttonsPressed[button] = true
end

function love.wheelmoved(dx, dy)
    love.mouse.wheelDelta = (love.mouse.wheelDelta or 0) + dy
end

function love.mouse.wasPressed(button)
    return love.mouse.buttonsPressed[button] or false
end

function love.update(dt)
    Timer.update(dt)
    gStateMachine:update(dt)

    love.keyboard.keysPressed = {}
    love.mouse.buttonsPressed = {}
    love.mouse.wheelDelta = 0
end

function love.draw()
    local state = gStateMachine.current

    if state.usesPush == false then
        -- Native-resolution path (3D): draw straight to the screen, which has a
        -- depth buffer (conf.lua). love.run clears color and depth each frame.
        love.graphics.setDepthMode('lequal', true)
        state:render()

        -- 2D overlay at native resolution, never occluded by 3D depth
        love.graphics.setDepthMode()
        if state.renderHUD then
            state:renderHUD()
        end
    else
        -- Virtual-resolution path (2D): push's canvas has no depth buffer
        love.graphics.setDepthMode()
        push:apply('start')
        state:render()
        push:apply('end')
    end
end

-- `love . --autotest`: scripted headless playthrough (tests/autotest.lua).
-- Never loaded in normal play.
for _, a in ipairs(arg or {}) do
    if a == '--autotest' then require 'tests/autotest' end
end

-- `love . --farm-shots`: reviewer screenshots of the farm (tests/farm_shots.lua,
-- development only; not in the package). Never loaded in normal play.
for _, a in ipairs(arg or {}) do
    if a == '--farm-shots' then require 'tests/farm_shots' end
end

-- `love . --backrooms-shots`: deterministic backrooms screenshots and frame
-- timing (tests/backrooms_shots.lua, development only; not in the package).
for _, a in ipairs(arg or {}) do
    if a == '--backrooms-shots' then require 'tests/backrooms_shots' end
    if a == '--ui-shots' then require 'tests/ui_shots' end
end

-- `love . --zone-maps`: top-down zone map renders for visual review (tests/zone_maps.lua,
-- development only; not in the package).
for _, a in ipairs(arg or {}) do
    if a == '--zone-maps' then require 'tests/zone_maps' end
end

-- `love . --fall-shot`: mid-fade pit-death screenshot (tests/fall_shot.lua, development only).
for _, a in ipairs(arg or {}) do
    if a == '--fall-shot' then require 'tests/fall_shot' end
    if a == '--silhouette-shot' then require 'tests/silhouette_shot' end
end

-- dev-only: love . --horror-shot
for _, a in ipairs(arg or {}) do
    if a == '--horror-shot' then require 'tests/horror_shot' end
end
