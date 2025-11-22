local class = require 'ext.class'
local table = require 'ext.table'
-- [FIX] require correct path (ext.func instead of ext-boost.func)
local func = require 'ext.func'

-- 流式迭代器封装
local Iter = class()

function Iter:init(next_f, state, val)
    self.next = next_f
    self.state = state
    self.curr = val
end

-- 使对象本身可调用，作为 for 循环的迭代器
function Iter:__call()
    local r = table.pack(self.next(self.state, self.curr))
    if r[1] == nil then return nil end
    self.curr = r[1]
    return table.unpack(r)
end

-- 工厂方法
function Iter.of(t)
    return Iter(ipairs(t))
end

function Iter.pairs(t)
    return Iter(pairs(t))
end

function Iter.range(a, b, s)
    s = s or 1
    -- 初始化计数器
    local c = a - s
    return Iter(function()
        c = c + s
        -- 检查边界
        if (s > 0 and c > b) or (s < 0 and c < b) then return nil end
        return c
    end)
end

-- 转换操作
function Iter:filter(fn)
    local n, s = self.next, self.state
    local prev_val = self.curr
    local pred = func.P.compile(fn)
    
    return Iter(function(s0, v)
        if v ~= nil then prev_val = v end
        while true do
            local results = table.pack(n(s0, prev_val))
            local val = results[1]
            prev_val = val
            if val == nil then return nil end
            if pred(table.unpack(results)) then 
                return table.unpack(results)
            end
        end
    end, s, self.curr)
end

function Iter:map(fn)
    local n, s = self.next, self.state
    local prev_val = self.curr
    local mapper = func.P.compile(fn)

    return Iter(function(s0, v)
        if v ~= nil then prev_val = v end
        local results = table.pack(n(s0, prev_val))
        local val = results[1]
        prev_val = val
        if val == nil then return nil end
        return mapper(table.unpack(results))
    end, s, self.curr)
end

-- 终端操作
function Iter:toTable()
    local t = table()
    for v in self do
        t:insert(v)
    end
    return t
end

function Iter:reduce(fn, acc)
    local reducer = func.P.compile(fn)
    local first_step = true
    
    for v in self do
        if first_step and acc == nil then
            acc = v
            first_step = false
        else
            acc = reducer(acc, v)
            first_step = false
        end
    end
    return acc
end

function Iter:count()
    local c = 0
    for _ in self do c = c + 1 end
    return c
end

return Iter