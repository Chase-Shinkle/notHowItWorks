-- Procedural mesh helpers for g3d (z is up, matching g3d.camera's default).
-- Vertex layout matches g3d's model.vertexFormat:
--   {x, y, z, u, v, nx, ny, nz, r, g, b, a}

-- Axis-aligned box centred on the origin with size (sx, sy, sz).
-- Returns a vertex table for g3d.newModel (36 vertices, outward normals).
function NewBoxVerts(sx, sy, sz, color)
    sx, sy, sz = sx or 1, sy or sx or 1, sz or sx or 1
    local hx, hy, hz = sx / 2, sy / 2, sz / 2
    local r, g, b, a = 1, 1, 1, 1
    if color then r, g, b, a = color[1], color[2], color[3], color[4] or 1 end

    -- each face: normal and its 4 corners, counter-clockwise seen from outside
    local faces = {
        {{ 1, 0, 0}, {{ hx,-hy,-hz}, { hx, hy,-hz}, { hx, hy, hz}, { hx,-hy, hz}}},
        {{-1, 0, 0}, {{-hx, hy,-hz}, {-hx,-hy,-hz}, {-hx,-hy, hz}, {-hx, hy, hz}}},
        {{ 0, 1, 0}, {{ hx, hy,-hz}, {-hx, hy,-hz}, {-hx, hy, hz}, { hx, hy, hz}}},
        {{ 0,-1, 0}, {{-hx,-hy,-hz}, { hx,-hy,-hz}, { hx,-hy, hz}, {-hx,-hy, hz}}},
        {{ 0, 0, 1}, {{-hx,-hy, hz}, { hx,-hy, hz}, { hx, hy, hz}, {-hx, hy, hz}}},
        {{ 0, 0,-1}, {{-hx, hy,-hz}, { hx, hy,-hz}, { hx,-hy,-hz}, {-hx,-hy,-hz}}},
    }
    local uvs = {{0, 1}, {1, 1}, {1, 0}, {0, 0}}

    local verts = {}
    for _, face in ipairs(faces) do
        local n, c = face[1], face[2]
        for _, i in ipairs({1, 2, 3, 1, 3, 4}) do
            local p = c[i]
            verts[#verts + 1] = {p[1], p[2], p[3], uvs[i][1], uvs[i][2], n[1], n[2], n[3], r, g, b, a}
        end
    end
    return verts
end
