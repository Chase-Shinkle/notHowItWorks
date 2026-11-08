-- Runtime backrooms effect isolation toggles (Mac black-square diagnosis). All effects default ON.
-- F1..F9 or Shift+1..Shift+9 flip one effect each; Shift+0 flips a render-info readout. Works only in the
-- backrooms state, never needs a reload, and is deliberately not listed in the controls hint.
EffectToggles = {
    list = {
        {id = 'post',    key = 1, label = 'POST'},      -- whole camcorder post pass
        {id = 'bloom',   key = 2, label = 'BLOOM'},
        {id = 'side',    key = 3, label = 'SIDEFILL'},  -- blurred side fill (off = plain dark)
        {id = 'idle',    key = 4, label = 'STILLNESS'}, -- stillness vignette
        {id = 'zone',    key = 5, label = 'ZONEDARK'},  -- zone ambient + fog darkening in the scene shader
        {id = 'outage',  key = 6, label = 'OUTAGE'},    -- light outage / flash darkening
        {id = 'sil',     key = 7, label = 'SILHOUETTE'},
        {id = 'fall',    key = 8, label = 'FALLFADE'},  -- visual fade only; fall gameplay untouched
        {id = 'distant', key = 9, label = 'DISTANT'},   -- distant sound events
    },
    state = {},
    info = false,
}
for _, e in ipairs(EffectToggles.list) do EffectToggles.state[e.id] = true end

function EffectToggles.on(id) return EffectToggles.state[id] ~= false end

function EffectToggles.toggle(index)
    local e = EffectToggles.list[index]
    if not e then return end
    EffectToggles.state[e.id] = not EffectToggles.state[e.id]
    if e.id == 'sil' and not EffectToggles.state.sil and Silhouette then Silhouette.clearActive() end
end

-- Returns the toggle index (1..9, 0 = info) for a key event, or nil. Mac-safe: F-keys, or a Shift +
-- digit matched by scancode (shifted symbols like '!' never reach `key`; scancode stays '1'..'9').
function EffectToggles.indexFor(key, scancode)
    local n = key and key:match('^f(%d)$')
    if n and tonumber(n) >= 1 then return tonumber(n) end
    if love.keyboard.isDown('lshift', 'rshift') then
        for _, k in ipairs({scancode, key}) do
            local d = k and (k:match('^%d$') or k:match('^kp(%d)$'))
            if d then return tonumber(d) end
        end
        local sym = {['!']=1, ['@']=2, ['#']=3, ['$']=4, ['%']=5, ['^']=6, ['&']=7, ['*']=8, ['(']=9, [')']=0}
        return sym[key]
    end
end

-- true when the key was consumed
function EffectToggles.handleKey(key, scancode)
    local st = gStateMachine and gStateMachine.current
    if not (st and st.isBackroomsState) then return false end
    local i = EffectToggles.indexFor(key, scancode)
    if not i then return false end
    if i == 0 then EffectToggles.info = not EffectToggles.info else EffectToggles.toggle(i) end
    return true
end

function EffectToggles.offLabels()
    local out = {}
    for _, e in ipairs(EffectToggles.list) do
        if not EffectToggles.state[e.id] then out[#out + 1] = e.label end
    end
    return out
end

-- Native-resolution overlay, drawn after (outside) the post pass.
function EffectToggles.draw()
    local off = EffectToggles.offLabels()
    if #off == 0 and not EffectToggles.info then return end
    love.graphics.push('all')
    love.graphics.origin(); love.graphics.setScissor(); love.graphics.setShader()
    love.graphics.setBlendMode('alpha'); love.graphics.setDepthMode()
    love.graphics.setFont(gFonts['default'])
    local font = love.graphics.getFont()
    local ww = love.graphics.getWidth()
    local y = 8
    local function line(text)
        local w = font:getWidth(text) + 12
        local x = ww - w - 8
        love.graphics.setColor(0, 0, 0, 0.75); love.graphics.rectangle('fill', x, y, w, font:getHeight() + 6)
        love.graphics.setColor(1, 1, 0.4, 1); love.graphics.print(text, x + 6, y + 3)
        y = y + font:getHeight() + 8
    end
    if #off > 0 then line('OFF: ' .. table.concat(off, ' ')) end
    if EffectToggles.info then
        local ok, text = pcall(function()
            local w, h = love.graphics.getDimensions()
            local pw, ph = love.graphics.getPixelDimensions()
            local name, ver, vendor, device = love.graphics.getRendererInfo()
            return string.format('win %dx%d px %dx%d dpi %.2f %s', w, h, pw, ph, love.graphics.getDPIScale(), tostring(name))
        end)
        line(ok and text or 'render info unavailable')
    end
    love.graphics.pop()
end
