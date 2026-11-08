-- Dev-only: `love . --silhouette-shot --run-seed=2026` with BR_OUT=<file.png>.
-- Searches generated levels for a real eligible long hall, then FORCES the
-- silhouette past its cooldown (Silhouette.debugForce) and captures one frame.
-- The appearance is forced, not a natural spawn.
local state, frames, shot, phase = nil, 0, false, 'search'
local origUpdate, origDraw = love.update, love.draw
local level = 1
local function search()
    local room = state.room
    local cols = room:solidColliders()
    local s = room.spawn
    for gx = -60, 60 do for gy = -60, 60 do
        local x, y = s[1] + gx * 0.5, s[2] + gy * 0.5
        for k = 0, 3 do
            local dir = k * math.pi / 2
            -- player cell must be open at body height (not inside a wall)
            local open = true
            for _, c in ipairs(cols) do
                if x >= c.min[1] - 0.4 and x <= c.max[1] + 0.4 and y >= c.min[2] - 0.4 and y <= c.max[2] + 0.4
                    and c.max[3] > 0.3 and c.min[3] < 1.5 then open = false; break end
            end
            if open and Silhouette.findSpot(cols, x, y, s[3], dir) then return x, y, s[3], dir end
        end
    end end
end
function love.update(dt)
    frames = frames + 1
    if frames == 1 then gStateMachine:change('backrooms'); state = gStateMachine.current end
    if frames > 2 and phase == 'search' then
        local x, y, z, dir = search()
        if x then
            state.player:setPosition(x, y, z)
            local ex, ey, ez = state.player:eyePosition()
            g3d.camera.lookInDirection(ex, ey, ez, dir, 0)
            print(string.format('[sil-shot] level %d pos %.1f,%.1f dir %.2f', level, x, y, dir))
            phase = 'force'
        else
            level = level + 1
            if level > state:levelCount() then print('[sil-shot] no eligible hall'); love.event.quit(); return end
            state:loadRoom(level)
        end
        return
    end
    if phase == 'force' then
        local _, p = g3d.camera.getDirectionPitch()
        local dir = g3d.camera.getDirectionPitch()
        assert(Silhouette.debugForce(state.room:solidColliders(), state.player, dir), 'force failed')
        print(string.format('[sil-shot] FORCED figure at %.1f,%.1f (%.1f m away)', Silhouette.active.x, Silhouette.active.y,
            math.sqrt((Silhouette.active.x - state.player.x) ^ 2 + (Silhouette.active.y - state.player.y) ^ 2)))
        phase = 'wait'; frames = 3
        return
    end
    if phase == 'wait' then
        origUpdate(1 / 60)
        if Silhouette.active and Silhouette.active.t > 2 and not shot then shot = 'pending' end
        if frames % 60 == 0 then print('[sil-shot] f', frames, Silhouette.active and Silhouette.active.t, state.fall and 'fall', state.roomIndex) end
        if frames > 900 then love.event.quit() end
    end
end
function love.draw()
    origDraw()
    if shot == 'pending' then
        shot = 'taken'
        love.graphics.captureScreenshot(function(d)
            d:encode('png', 'tmpshot.png')
            local out = os.getenv('BR_OUT') or '/workspace/qa/horror/silhouette.png'
            local fh = io.open(out, 'wb'); fh:write(love.filesystem.read('tmpshot.png')); fh:close()
            print('[sil-shot] saved ' .. out); love.event.quit()
        end)
    end
end
