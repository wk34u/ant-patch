local ecs = ...

local m = ecs.component "mesh"

local bgfx = require "bgfx"
local declmgr = import_package "ant.render".declmgr

local proxy_vb = {}
function proxy_vb:__index(k)
    if k == "handle" then
        assert(#self.memory <= 3 and (type(self.memory[1]) == "userdata" or type(self.memory[1]) == "string"))
        local membuf = bgfx.memory_buffer(table.unpack(self.memory))
        local h = bgfx.create_vertex_buffer(membuf, declmgr.get(self.declname).handle)
        self.handle = h
        return h
    end
end

local proxy_ib = {}
function proxy_ib:__index(k)
    if k == "handle" then
        assert(#self.memory <= 3 and (type(self.memory[1]) == "userdata" or type(self.memory[1]) == "string"))
        local membuf = bgfx.memory_buffer(table.unpack(self.memory))
        local h = bgfx.create_index_buffer(membuf, self.flag)
        self.handle = h
        return h
    end
end

function m:init()
    local vb = self.vb
    for _, v in ipairs(vb) do
        setmetatable(v, proxy_vb)
    end
    local ib = self.ib
    if ib then
        setmetatable(ib, proxy_ib)
    end
    return self
end
