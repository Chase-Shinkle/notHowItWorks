-- Shared UI helpers: cached display fonts and a keyboard/mouse button Menu.
-- Pure layout and hit-testing so they run under the mocked LÖVE API.
UI = {fontPath = UI_FONT_FILE}

local fontCache = {}

-- Display font at `size` px (rounded, clamped), cached per path and size.
-- A missing or broken font file falls back to the built-in font (Assets.loadFont).
function UI.font(size)
    size = math.floor(math.max(UI_FONT_MIN_SIZE, math.min(UI_FONT_MAX_SIZE, size or 16)) + 0.5)
    local key = tostring(UI.fontPath) .. '@' .. size
    local font = fontCache[key]
    if not font then
        font = Assets.loadFont(UI.fontPath, size)
        fontCache[key] = font
    end
    return font
end

-- Font size for `frac` of the window height (e.g. 0.05 = 5%).
function UI.scaledSize(frac, windowHeight)
    windowHeight = windowHeight or select(2, love.graphics.getDimensions())
    return windowHeight * frac
end

function UI.clearFontCache() fontCache = {} end

local function identity(x, y) return x, y end

-- Menu ----------------------------------------------------------------------
-- items: {{label = 'Play Game', onActivate = fn}, ...}
-- opts.mapper(x, y) converts raw window mouse coordinates into the menu's
-- coordinate space (push:toGame for the title, identity for native screens).
local Menu = {}
Menu.__index = Menu
UI.Menu = Menu

function Menu.new(items, opts)
    local self = setmetatable({}, Menu)
    self.items = items
    self.rects = {}
    self.index = 1
    self.mapper = opts and opts.mapper or identity
    return self
end

-- Stacks buttons vertically, centred on cx, first button's top at y.
function Menu:layout(cx, y, w, h, gap)
    self.rects = {}
    for i = 1, #self.items do
        self.rects[i] = {x = cx - w / 2, y = y + (i - 1) * (h + gap), w = w, h = h}
    end
end

-- Index of the button under (x, y) in menu space, or nil.
function Menu:hit(x, y)
    for i, r in ipairs(self.rects) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return i end
    end
    return nil
end

function Menu:activate(i)
    local item = self.items[i or self.index]
    if item and item.onActivate then item.onActivate() end
end

-- Hover from raw window coordinates; moves the highlight when over a button.
function Menu:mousemoved(rx, ry)
    local i = self:hit(self.mapper(rx, ry))
    if i then self.index = i end
    return i
end

-- Left click from raw window coordinates; activates only the button hit.
function Menu:mousepressed(rx, ry, button)
    if (button or 1) ~= 1 then return false end
    local i = self:hit(self.mapper(rx, ry))
    if not i then return false end
    self.index = i
    self:activate(i)
    return true
end

-- Returns true when the key was handled.
function Menu:keypressed(key)
    local n = #self.items
    if n == 0 then return false end
    if key == 'up' or key == 'w' then
        self.index = (self.index - 2) % n + 1
    elseif key == 'down' or key == 's' then
        self.index = self.index % n + 1
    elseif key == 'return' or key == 'kpenter' or key == 'space' then
        self:activate()
    else
        return false
    end
    return true
end

-- Button drawing --------------------------------------------------------------
-- Largest scale (<= 1) at which `label` fits `maxWidth` in `font`.
function UI.fitScale(font, label, maxWidth)
    local w = font:getWidth(label)
    if w <= maxWidth or w == 0 then return 1 end
    return maxWidth / w
end

local function setColor(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
end

-- Frame, fill (brighter when highlighted) and centred label scaled to fit.
function UI.drawButton(rect, label, highlighted, font, alpha)
    local g = love.graphics
    local lw = math.max(1, math.floor(rect.h / 16))
    setColor(highlighted and UI_BUTTON_FILL_HI or UI_BUTTON_FILL, alpha)
    g.rectangle('fill', rect.x, rect.y, rect.w, rect.h, rect.h / 6, rect.h / 6)
    setColor(UI_BUTTON_FRAME, alpha)
    g.setLineWidth(highlighted and lw * 2 or lw)
    g.rectangle('line', rect.x, rect.y, rect.w, rect.h, rect.h / 6, rect.h / 6)
    g.setLineWidth(1)
    g.setFont(font)
    local s = UI.fitScale(font, label, rect.w * (1 - 2 * UI_BUTTON_PAD))
    s = math.min(s, (rect.h * 0.8) / math.max(1, font:getHeight()))
    setColor(highlighted and UI_BUTTON_TEXT_HI or UI_BUTTON_TEXT, alpha)
    local tw, th = font:getWidth(label) * s, font:getHeight() * s
    g.print(label, math.floor(rect.x + (rect.w - tw) / 2), math.floor(rect.y + (rect.h - th) / 2), 0, s, s)
    g.setColor(1, 1, 1, 1)
end

function Menu:draw(font, alpha)
    for i, item in ipairs(self.items) do
        UI.drawButton(self.rects[i], item.label, i == self.index, font, alpha)
    end
end
