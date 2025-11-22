local class = require 'ext.class'
local table = require 'ext.table'

local OrderedMap = class()

function OrderedMap:init(t)
    -- [修复] 使用 rawset 初始化内部字段，避免触发 __newindex 导致死循环
    rawset(self, '_keys', table())
    rawset(self, '_values', {})
    
    if t then
        -- 注意：普通 table pairs 迭代顺序未定义
        for k, v in pairs(t) do
            self:set(k, v)
        end
    end
end

function OrderedMap:set(k, v)
    -- 如果是新键且值不为 nil，追加到键列表
    if self._values[k] == nil and v ~= nil then
        self._keys:insert(k)
    -- 如果值为 nil，删除键
    elseif v == nil then
        self._keys:removeObject(k)
    end
    self._values[k] = v
    return self
end

function OrderedMap:keys()
    return self._keys
end

function OrderedMap:values()
    local t = table()
    for _, k in ipairs(self._keys) do
        t:insert(self._values[k])
    end
    return t
end

function OrderedMap:iter()
    local i = 0
    return function()
        i = i + 1
        if i > #self._keys then return nil end
        local k = self._keys[i]
        return k, self._values[k]
    end
end

-- 按 Key 排序
function OrderedMap:sort(cmp)
    self._keys:sort(cmp)
    return self
end

-- 元方法支持
function OrderedMap:__newindex(k, v)
    self:set(k, v)
end

function OrderedMap:__index(k)
    -- 优先查找类方法，然后查找值
    -- 注意：这里访问 self._values 是安全的，因为 init 中已经通过 rawset 创建了该字段
    return OrderedMap[k] or self._values[k]
end

function OrderedMap:__pairs()
    return self:iter()
end

function OrderedMap:__tostring()
    local parts = table()
    for k, v in self:iter() do
        parts:insert(tostring(k) .. "=" .. tostring(v))
    end
    return "{" .. parts:concat(",") .. "}"
end

return OrderedMap