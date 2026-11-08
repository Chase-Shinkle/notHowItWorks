-- Minecraft-style seed hotbar for the backrooms HUD. layout() is pure (testable
-- without a GPU); draw() renders frames, seed-bag icons, key numbers and counts.
Hotbar = {}

HOTBAR_SLOT_FRAC = 0.07      -- slot size as a fraction of window height
HOTBAR_SLOT_MIN, HOTBAR_SLOT_MAX = 32, 96
HOTBAR_GAP_FRAC = 0.1        -- gap between slots, fraction of slot size
HOTBAR_MARGIN_FRAC = 0.025   -- distance from the bottom edge, fraction of height

-- Slot rects for `count` slots, centred at the bottom; shrinks to fit narrow windows.
function Hotbar.layout(w, h, count)
    count = count or #SEED_TYPES
    local size = math.max(HOTBAR_SLOT_MIN, math.min(HOTBAR_SLOT_MAX, h * HOTBAR_SLOT_FRAC))
    local gap = size * HOTBAR_GAP_FRAC
    local total = count * size + (count - 1) * gap
    if total > w - 8 then
        size = (w - 8) / (count + (count - 1) * HOTBAR_GAP_FRAC)
        gap = size * HOTBAR_GAP_FRAC
        total = count * size + (count - 1) * gap
    end
    local x0 = (w - total) / 2
    local y = h - size - math.max(6, h * HOTBAR_MARGIN_FRAC)
    local slots = {}
    for i = 1, count do slots[i] = {x = x0 + (i - 1) * (size + gap), y = y, w = size, h = size} end
    return {slots = slots, size = size, x = x0, y = y, w = total, h = size}
end

-- seeds: counts by type; selected: seed type; usable(type) -> bool (room uses it).
function Hotbar.draw(w, h, seeds, selected, usable)
    local g = love.graphics
    local lay = Hotbar.layout(w, h, #SEED_TYPES)
    local fsz = math.max(14, math.floor(lay.size * 0.36))
    Hotbar.fonts = Hotbar.fonts or {}
    local font = Hotbar.fonts[fsz]
    if not font then font = love.graphics.newFont(fsz); Hotbar.fonts[fsz] = font end   -- plain default font, readable
    Hotbar.last = {selected = selected, counts = {}, usable = {}}   -- what was drawn (tests)
    for i, t in ipairs(SEED_TYPES) do
        local r = lay.slots[i]
        local n = seeds[t] or 0
        local isUsable = (not usable) or usable(t)
        local dim = (n == 0 or not isUsable) and 0.4 or 1
        local isSel = t == selected
        Hotbar.last.counts[i], Hotbar.last.usable[i] = n, isUsable
        g.setColor(0.05, 0.05, 0.05, 0.55)
        g.rectangle('fill', r.x, r.y, r.w, r.h, 4, 4)
        local tex = gTextures and gTextures['seedbag-' .. t]
        if tex then
            local iw, ih = tex:getDimensions()
            local s = math.min(r.w * 0.62 / iw, r.h * 0.62 / ih)
            g.setColor(1, 1, 1, dim)
            g.draw(tex, r.x + (r.w - iw * s) / 2, r.y + (r.h - ih * s) / 2, 0, s, s)
        end
        g.setFont(font)
        local function outlined(txt, x, y, a)
            g.setColor(0, 0, 0, 0.95)
            for _, o in ipairs({{-1,-1},{1,-1},{-1,1},{1,1},{0,2},{2,0},{-2,0},{0,-2}}) do g.print(txt, x + o[1], y + o[2]) end
            g.setColor(1, 1, 1, a)
            g.print(txt, x, y)
        end
        outlined(tostring(i), r.x + 5, r.y + 2, 0.85 * dim + 0.15)
        local txt = tostring(n)
        outlined(txt, r.x + r.w - font:getWidth(txt) - 5, r.y + r.h - font:getHeight() - 1, dim)
        g.setLineWidth(isSel and 4 or 2)
        if isSel then g.setColor(1, 0.95, 0.4, 1) else g.setColor(0.8, 0.8, 0.8, 0.5 * dim + 0.2) end
        g.rectangle('line', r.x, r.y, r.w, r.h, 4, 4)
    end
    g.setLineWidth(1)
    g.setColor(1, 1, 1, 1)
    return lay
end
