local class = require 'ext.class'
local table = require 'ext.table'

local Set = class()

function Set:init(t)
    self.data = {}
    if t then
        for _, v in pairs(t) do
            self.data[v] = true
        end
    end
end

function Set:add(v)
    self.data[v] = true
    return self
end

function Set:remove(v)
    self.data[v] = nil
    return self
end

function Set:contains(v)
    return self.data[v] ~= nil
end

function Set:values()
    local t = table()
    for k in pairs(self.data) do
        t:insert(k)
    end
    return t
end

function Set:union(other)
    local r = Set()
    for k in pairs(self.data) do r:add(k) end
    if other then
        for k in pairs(other.data) do r:add(k) end
    end
    return r
end

function Set:intersection(other)
    local r = Set()
    if other then
        for k in pairs(self.data) do
            if other.data[k] then r:add(k) end
        end
    end
    return r
end

function Set:difference(other)
    local r = Set()
    for k in pairs(self.data) do
        if not (other and other.data[k]) then r:add(k) end
    end
    return r
end

function Set:len()
    local c = 0
    for _ in pairs(self.data) do c = c + 1 end
    return c
end

-- 运算符重载
function Set.__add(a, b) return a:union(b) end
function Set.__sub(a, b) return a:difference(b) end
function Set.__mul(a, b) return a:intersection(b) end

function Set:__tostring()
    local vals = self:values()
    -- 排序以保证调试输出的一致性 (如果是字符串或数字)
    table.sort(vals, function(a,b) return tostring(a) < tostring(b) end)
    return "Set{" .. vals:concat(",") .. "}"
end

return Set