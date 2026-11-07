Entity = Class{}

function Entity:init(def)
    -- position and movement
    self.x = def.x
    self.y = def.y

    self.dx = 0
    self.dy = 0

    -- dimensions
    self.width = def.width
    self.height = def.height

    -- rendering
    self.texture = def.texture
    self.quad = def.quad            -- optional specific quad to use
    self.rotation = def.rotation or 0
    self.scaleX = def.scaleX or 1
    self.scaleY = def.scaleY or 1

    -- optional state machine for complex entities
    self.stateMachine = def.stateMachine
end

function Entity:changeState(state, params)
    if self.stateMachine then
        self.stateMachine:change(state, params)
    end
end

function Entity:update(dt)
    -- state machine update if present
    if self.stateMachine then
        self.stateMachine:update(dt)
    end
end

function Entity:render()
    -- simple centered drawing with no assumptions about quads or direction
    if self.texture then
        local quadOrTable = self.quad or gFrames[self.texture]
        local cx = math.floor(self.x + (self.width or 0) / 2)
        local cy = math.floor(self.y + (self.height or 0) / 2)

        if quadOrTable and type(quadOrTable) ~= 'table' then
            -- it's a single Quad
            love.graphics.draw(
                gTextures[self.texture],
                quadOrTable,
                cx,
                cy,
                self.rotation,
                self.scaleX,
                self.scaleY,
                (self.width or 0) / 2,
                (self.height or 0) / 2
            )
        else
            -- draw the whole image (no quad)
            love.graphics.draw(
                gTextures[self.texture],
                cx - (self.width or 0) / 2,
                cy - (self.height or 0) / 2,
                self.rotation,
                self.scaleX,
                self.scaleY
            )
        end
    end

    -- render state machine effects if present
    if self.stateMachine then
        self.stateMachine:render()
    end
end
