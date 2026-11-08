-- LÖVE configuration. Loaded before main.lua.
function love.conf(t)
    t.identity = 'not-how-it-works'
    t.version = '11.5'

    t.window.title = 'Back to Farming'
    t.window.width = 800
    t.window.height = 800
    t.window.resizable = true
    t.window.fullscreen = true
    t.window.fullscreentype = 'desktop'
    t.window.highdpi = true   -- code is DPI-aware (BackroomsLook dpiscale canvases, commit 0188d66)
    t.window.vsync = 1

    -- g3d needs a depth buffer on the main framebuffer: states that opt out of
    -- push (usesPush = false) draw 3D straight to the screen.
    t.window.depth = 24
end
