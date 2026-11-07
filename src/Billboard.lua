-- Camera-facing sprites for old farm assets in the 3D backrooms.
--
-- A billboard is a g3d model of one upright quad standing on (x, y, z). The
-- quad is built in the local plane x = 0 facing +x, and every frame its yaw
-- (rotation about z) is set so +x points at the camera. This is cylindrical
-- billboarding: sprites turn to face the player but stay upright.

Billboard = Class{}

local atan2 = math.atan2 or math.atan   -- Lua 5.3+ has no math.atan2

-- Upright quad: width w along local y, height h along z, base at z = 0,
-- normal +x. Seen from +x, u runs left -> right and v top -> bottom, so the
-- image is not mirrored. Vertex layout as NewBoxVerts.
function NewBillboardVerts(w, h)
    local hw = w / 2
    local corners = {{0, -hw, 0}, {0, hw, 0}, {0, hw, h}, {0, -hw, h}}
    local uvs = {{0, 1}, {1, 1}, {1, 0}, {0, 0}}
    local verts = {}
    for _, i in ipairs({1, 2, 3, 1, 3, 4}) do
        local p = corners[i]
        verts[#verts + 1] = {p[1], p[2], p[3], uvs[i][1], uvs[i][2], 1, 0, 0, 1, 1, 1, 1}
    end
    return verts
end

-- Yaw (radians, about z) that turns a quad at (bx, by) to face (cx, cy).
-- Returns nil when the camera is directly above/below (no defined yaw).
function Billboard.yawToward(bx, by, cx, cy)
    local dx, dy = cx - bx, cy - by
    if dx * dx + dy * dy < 1e-10 then return nil end
    return atan2(dy, dx)
end

-- Pixel shader that discards transparent texels, so the empty parts of a
-- sprite don't write depth and hide what is behind them. Built once, lazily;
-- falls back to g3d's default shader if compilation is not possible.
local alphaShader
local function getAlphaShader()
    if alphaShader == nil then
        alphaShader = false
        if love.graphics.newShader and g3d.shaderpath then
            local ok, shader = pcall(love.graphics.newShader, g3d.shaderpath, [[
                vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 pixcoord) {
                    vec4 texel = Texel(tex, texcoord) * color;
                    if (texel.a < 0.1) { discard; }
                    return texel;
                }
            ]])
            if ok and shader then alphaShader = shader end
        end
    end
    return alphaShader or nil
end
Billboard.getAlphaShader = getAlphaShader   -- nil if it fell back (checked by tests/autotest.lua)

-- def = {texture = <gTextures key or Image>, pos = {x, y, z}, height = h,
--        width = w (optional, default keeps the image aspect ratio),
--        color = {r, g, b, a} (optional tint)}
function Billboard:init(def)
    local texture = def.texture
    if type(texture) == 'string' then
        self.textureName = texture
        texture = gTextures[texture]
    end
    assert(texture, 'billboard texture missing: ' .. tostring(def.texture))
    self.texture = texture

    self.height = def.height or 1
    local tw, th = 1, 1
    if texture.getDimensions then tw, th = texture:getDimensions() end
    self.width = def.width or self.height * tw / math.max(th, 1)
    self.color = def.color or {1, 1, 1, 1}

    local pos = def.pos or {0, 0, 0}
    self.x, self.y, self.z = pos[1], pos[2], pos[3] or 0
    self.yaw = def.yaw or 0
    self.model = g3d.newModel(NewBillboardVerts(self.width, self.height), texture,
        {self.x, self.y, self.z}, {0, 0, self.yaw})
end

-- Turn to face a camera at (cx, cy). Returns the yaw now in use.
function Billboard:faceCamera(cx, cy)
    local yaw = Billboard.yawToward(self.x, self.y, cx, cy)
    if yaw then
        self.yaw = yaw
        self.model:setRotation(0, 0, yaw)
    end
    return self.yaw
end

-- World-space facing direction (the quad's normal), for tests and debugging.
function Billboard:facing()
    return math.cos(self.yaw), math.sin(self.yaw), 0
end

function Billboard:draw()
    love.graphics.setColor(self.color)
    self.model:draw(getAlphaShader())
    love.graphics.setColor(1, 1, 1, 1)
end

-- Face every billboard in `list` towards the camera and draw them far to
-- near, after the opaque room geometry (see Room:draw).
function Billboard.drawAll(list, cx, cy)
    for _, b in ipairs(list) do
        b:faceCamera(cx, cy)
        b.distanceSq = (b.x - cx) ^ 2 + (b.y - cy) ^ 2
    end
    local sorted = {}
    for i, b in ipairs(list) do sorted[i] = b end
    table.sort(sorted, function(a, b) return a.distanceSq > b.distanceSq end)
    for _, b in ipairs(sorted) do b:draw() end
end
