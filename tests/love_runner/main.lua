-- Runs a plain-Lua test script under LÖVE's LuaJIT, from the repo root:
--   love tests/love_runner tests/run.lua
--   love tests/love_runner tests/reachability.lua
-- The script replaces the global `love` with its own mock and ends with
-- os.exit(), so LÖVE's main loop never starts.
local script
for _, a in ipairs(arg) do
    if type(a) == 'string' and a:match('%.lua$') and not a:match('love_runner') then script = a end
end
if not script then
    io.stderr:write('usage: love tests/love_runner <script.lua>\n')
    os.exit(2)
end
io.stdout:setvbuf('line')
print('[love_runner] ' .. tostring(jit and jit.version or _VERSION) .. ' running ' .. script)
local ok, err = xpcall(function() dofile(script) end, debug.traceback)
if not ok then
    io.stderr:write('[love_runner] error: ' .. tostring(err) .. '\n')
    os.exit(3)
end
-- A script that returns without calling os.exit is treated as a failure.
io.stderr:write('[love_runner] script returned without os.exit\n')
os.exit(4)
