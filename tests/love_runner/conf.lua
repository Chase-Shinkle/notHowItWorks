-- Headless LÖVE shell used only to run the Lua test scripts with LÖVE's real
-- LuaJIT. No window, audio or graphics module is created.
function love.conf(t)
    t.window = false
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.sound = false
    t.modules.joystick = false
end
