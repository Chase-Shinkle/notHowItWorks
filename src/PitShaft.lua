-- Render-only deep shaft for generated pit / gap modules (no collision, no layout).
--
-- The module's real void floor sits only LEVELGEN_VOID_Z below the rim, so the
-- bottom shows. PitShaft.build(data) replaces what is drawn below the rim with
-- wallpapered shaft walls (the cell theme's wall texture) running PIT_SHAFT_DEPTH
-- metres down, a repeating trim ring every PIT_SHAFT_RHYTHM m (the "ledge"
-- rhythm), and brightness that recedes to black with depth BELOW THAT SHAFT'S
-- OWN RIM (never absolute z). A black cap closes the far end, already invisible.
--
-- Dimensions come from the module cell in data.meta (cx, cy, elev, dir, module)
-- via LevelGen.frame / LevelGen.MODULES (opening in module-local u, full cell
-- width in v, rotated by the travel direction), so any critical/optional pit or
-- gap at any elevation and rotation works. Ledges are not shafts and are skipped.
--
-- Fade is baked into vertex colours (works with or without the look shader); the
-- look shader additionally pulls fog toward black below the rim (uniforms
-- shaftRim / shaftFade, see shaders/backrooms.glsl) so yellow fog cannot light the bottom.
--
-- Result: {parts = {{models = {model...}, rim = z}...}, skip = {[boxIndex] = true}}.
-- `skip` lists the boxes whose *drawing* is replaced (the module's void floor and
-- the soil column under a pit plot); Room keeps their colliders unchanged.

PitShaft = {}

PIT_SHAFT_DEPTH = 18        -- m below the rim over which the walls fade to black (shaft is this deep)
PIT_SHAFT_STEP = 1          -- m per wall strip (vertex-colour fade resolution)
PIT_SHAFT_RHYTHM = 3        -- m between trim rings
PIT_SHAFT_FOG_FADE = 7      -- m below the rim over which fog colour goes to black (shader)
local INSET = 0.02          -- panels sit this far in front of the real walls (no z-fight)
local TRIM_H, TRIM_OUT = 0.22, 0.05
local TRIM_COLOR = {0.78, 0.7, 0.5, 1}

-- brightness factor at depth d (m) below the rim
function PitShaft.fade(d)
    if d <= 0 then return 1 end
    local t = 1 - d / PIT_SHAFT_DEPTH
    return t > 0 and t * t or 0
end

-- one vertical wall panel from a to b, between rim - d0 and rim - d1 (d0 < d1), as 1 strip
local function strip(out, a, b, n, rim, d0, d1, col, shade, tile)
    local rx, ry = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(rx * rx + ry * ry)
    local function v(p, d, u)
        local z = rim - d
        local f = PitShaft.fade(d)
        return {p[1], p[2], z, u / tile, -z / tile, n[1], n[2], 0,
            col[1] * shade * f, col[2] * shade * f, col[3] * shade * f, 1}
    end
    local tl, tr = v(a, d0, 0), v(b, d0, len)
    local bl, br = v(a, d1, 0), v(b, d1, len)
    -- counter-clockwise seen from the normal side: bl, br, tr, tl
    for _, p in ipairs({bl, br, tr, bl, tr, tl}) do out[#out + 1] = p end
end

local function boxHas(b, cell, def)
    -- box centre inside the module cell footprint
    local x0, y0 = cell.cx * LEVELGEN_CELL, cell.cy * LEVELGEN_CELL - LEVELGEN_CELL / 2
    return b.pos[1] > x0 and b.pos[1] < x0 + LEVELGEN_CELL and b.pos[2] > y0 and b.pos[2] < y0 + LEVELGEN_CELL
end

function PitShaft.build(data)
    local result = {parts = {}, skip = {}}
    local meta = data.meta
    if not meta or not meta.cells or not LevelGen or not gTextures then return result end
    local T = LEVELGEN_WALL
    local h = LEVELGEN_CELL / 2
    for _, c in ipairs(meta.cells) do
        local def = c.kind == 'module' and LevelGen.MODULES[c.module]
        if def and (c.module == 'pit' or c.module == 'gap') and c.dir then
            local u0, u1 = def.pitX0 or def.gapX0, def.pitX1 or LEVELGEN_CELL
            local f = LevelGen.frame(c.cx, c.cy, c.dir)
            local rim = c.elev
            -- theme + replaced boxes from the module's own void floor / soil column
            local themeName, pillar
            for i, b in ipairs(data.boxes) do
                if b.obstacle and b.kind == 'floor' and boxHas(b, c, def)
                    and math.abs(b.pos[3] + b.size[3] / 2 - LEVELGEN_VOID_Z) < 0.01 then
                    result.skip[i] = true
                    themeName = themeName or b.theme
                elseif b.kind == 'solid' and b.collide == false and not b.obstacle and boxHas(b, c, def)
                    and math.abs(b.pos[3] - b.size[3] / 2 - LEVELGEN_VOID_Z) < 0.01 then
                    result.skip[i] = true
                    pillar = b
                end
            end
            local theme = MATERIAL_THEMES[themeName or data.theme or '']
            local wallKey = theme and theme.wall or 'wall'
            local tex = gTextures[wallKey]
            local col
            if tex and not Assets.isPlaceholder(tex) then
                local t = theme and theme.tint or {1, 1, 1, 1}
                col = {t[1], t[2], t[3]}
                if tex.setWrap then tex:setWrap('repeat', 'repeat') end
            else
                tex = gTextures['wall'] or gTextures['white']
                col = theme and theme.fallbackColor or {0.84, 0.78, 0.38}
                if tex and tex.setWrap then tex:setWrap('repeat', 'repeat') end
            end

            local v0, v1 = h - T / 2 - INSET, -(h - T / 2 - INSET)
            -- inward-facing panels: {u_a, v_a, u_b, v_b, normal in module-local (nu, nv)}
            local faces = {
                {u0 + INSET, v0, u1 - INSET, v0, 0, -1},     -- left wall (+v side), faces -v
                {u0 + INSET, v1, u1 - INSET, v1, 0, 1},      -- right wall, faces +v
                {u0 + INSET, v1, u0 + INSET, v0, 1, 0},      -- near end, faces +u
                {u1 - INSET, v1, u1 - INSET, v0, -1, 0},     -- far end, faces -u
            }
            local wallVerts, trimVerts = {}, {}
            local d = f.d
            local p = f.p
            for _, fc in ipairs(faces) do
                local ax, ay = f.point(fc[1], fc[2])
                local bx, by = f.point(fc[3], fc[4])
                local nx = fc[5] * d[1] + fc[6] * p[1]
                local ny = fc[5] * d[2] + fc[6] * p[2]
                -- "right" seen from the normal side is (-ny, nx)
                local A, B = {ax, ay}, {bx, by}
                if (B[1] - A[1]) * (-ny) + (B[2] - A[2]) * nx < 0 then A, B = B, A end
                local n = {nx, ny}
                local shade = math.abs(nx) > 0.5 and 0.85 or 0.92
                for dd = 0, PIT_SHAFT_DEPTH - PIT_SHAFT_STEP, PIT_SHAFT_STEP do
                    strip(wallVerts, A, B, n, rim, dd, dd + PIT_SHAFT_STEP, col, shade, ROOM_TEXTURE_TILE)
                end
                -- trim ring plates a little in front of the panel
                local ox, oy = nx * TRIM_OUT, ny * TRIM_OUT
                local TA, TB = {A[1] + ox, A[2] + oy}, {B[1] + ox, B[2] + oy}
                for dd = PIT_SHAFT_RHYTHM, PIT_SHAFT_DEPTH - PIT_SHAFT_RHYTHM, PIT_SHAFT_RHYTHM do
                    strip(trimVerts, TA, TB, n, rim, dd, dd + TRIM_H, TRIM_COLOR, 0.9, ROOM_TEXTURE_TILE)
                end
            end
            -- black cap closing the far end of the shaft
            local capZ = rim - PIT_SHAFT_DEPTH
            local capVerts = {}
            local c1x, c1y = f.point(u0, v1)
            local c2x, c2y = f.point(u1, v1)
            local c3x, c3y = f.point(u1, v0)
            local c4x, c4y = f.point(u0, v0)
            local function cv(x, y) return {x, y, capZ, 0, 0, 0, 0, 1, 0, 0, 0, 1} end
            local pts = {cv(c1x, c1y), cv(c2x, c2y), cv(c3x, c3y), cv(c4x, c4y)}
            -- winding by sign of the module frame (d x p is always +z, so fixed order faces up)
            for _, i in ipairs({1, 2, 3, 1, 3, 4}) do capVerts[#capVerts + 1] = pts[i] end

            local white = gTextures['white'] or tex
            local models = {g3d.newModel(wallVerts, tex, {0, 0, 0}),
                g3d.newModel(trimVerts, white, {0, 0, 0}),
                g3d.newModel(capVerts, white, {0, 0, 0})}
            if pillar then
                local verts = {}
                local top = pillar.pos[3] + pillar.size[3] / 2
                local color = pillar.color or {0.36, 0.25, 0.16, 1}
                for z = top, rim - PIT_SHAFT_DEPTH, -PIT_SHAFT_STEP do
                    local z0 = math.max(z - PIT_SHAFT_STEP, rim - PIT_SHAFT_DEPTH)
                    for _, v in ipairs(NewRoomBoxVerts(pillar.size[1], pillar.size[2], z - z0, color)) do
                        local zz = v[3] + (z + z0) / 2
                        local fd = PitShaft.fade(rim - zz)
                        v[1], v[2], v[3] = v[1] + pillar.pos[1], v[2] + pillar.pos[2], zz
                        v[9], v[10], v[11] = v[9] * fd, v[10] * fd, v[11] * fd
                        verts[#verts + 1] = v
                    end
                end
                models[#models + 1] = g3d.newModel(verts, gTextures['white'] or tex, {0, 0, 0})
            end
            result.parts[#result.parts + 1] = {models = models, rim = rim}
        end
    end
    return result
end

-- Draws the shafts of `parts` (Room.shafts). `look` is the shader or nil.
function PitShaft.draw(parts, look)
    for _, part in ipairs(parts) do
        if look then
            BackroomsLook.set('shaftRim', part.rim)
            BackroomsLook.set('shaftFade', PIT_SHAFT_FOG_FADE)
        end
        for _, m in ipairs(part.models) do m:draw(look) end
    end
    if look and #parts > 0 then BackroomsLook.set('shaftFade', 0) end
end
