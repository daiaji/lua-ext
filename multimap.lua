local class = require 'ext.class'
local table = require 'ext.table'

local MultiMap = class()

function MultiMap:init(t)
    self.data = {}
    if t then
        for k, v in pairs(t) do
            self:set(k, v)
        end
    end
end

function MultiMap:set(k, v)
    if not self.data[k] then
        self.data[k] = table()
    end
    self.data[k]:insert(v)
    return self
end

function MultiMap:get(k)
    return self.data[k] or table()
end

function MultiMap:iter()
    return pairs(self.data)
end

function MultiMap:__tostring()
    local parts = table()
    for k, vs in pairs(self.data) do
        parts:insert(tostring(k) .. "=[" .. vs:concat(",") .. "]")
    end
    return "MultiMap{" .. parts:concat("; ") .. "}"
end

return MultiMap