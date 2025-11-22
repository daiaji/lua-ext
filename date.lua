local class = require 'ext.class'
local os = require 'ext.os'
local math = require 'ext.math'

local Date = class()

-- 支持简单的 ISO8601 解析
function Date:init(t)
    if t == 'utc' then
        self.time = os.time() 
        self.is_utc = true
    elseif type(t) == 'string' then
        -- 尝试解析 YYYY-MM-DD HH:MM:SS
        local y, m, d, h, min, s = t:match("^(%d+)-(%d+)-(%d+)[ T](%d+):(%d+):(%d+)$")
        if not y then
            -- 尝试 YYYY-MM-DD
            y, m, d = t:match("^(%d+)-(%d+)-(%d+)$")
            h, min, s = 0, 0, 0
        end
        
        if y then
            self.time = os.time({
                year=y, month=m, day=d, hour=h, min=min, sec=s
            })
        else
            self.time = os.time()
        end
    elseif type(t) == 'table' then
        self.time = os.time(t)
    elseif type(t) == 'number' then
        self.time = t
    else
        self.time = os.time()
    end
end

function Date:add(t)
    local d = os.date("*t", self.time)
    d.year = d.year + (t.year or 0)
    d.month = d.month + (t.month or 0)
    d.day = d.day + (t.day or 0)
    d.hour = d.hour + (t.hour or 0)
    d.min = d.min + (t.min or 0)
    d.sec = d.sec + (t.sec or 0)
    self.time = os.time(d)
    return self
end

function Date:diff(other)
    return os.difftime(self.time, other.time)
end

function Date:format(f)
    return os.date(f or '%Y-%m-%d %H:%M:%S', self.time)
end

function Date.__add(d, t)
    local new_date = Date(d.time)
    return new_date:add(t)
end

function Date.__sub(a, b)
    if Date:isa(b) then
        return a:diff(b)
    else
        -- 假设减去的是秒数
        return Date(a.time - b)
    end
end

function Date:__tostring()
    return self:format()
end

return Date