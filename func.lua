local getmetatable, setmetatable = getmetatable, setmetatable
local type = type
local select = select

local P = {}
local P_mt = {}

local function is_P(v)
    return getmetatable(v) == P_mt
end

-- 辅助函数：求值
local function eval(val, ...)
    if is_P(val) then
        return val._fn(...)
    elseif type(val) == "function" then
        return val(...)
    else
        return val
    end
end

-- 算术操作符重载 (算术操作符在 Lua 5.1 中支持混合类型)
function P_mt:__add(b) return P.new(function(...) return eval(self, ...) + eval(b, ...) end) end
function P_mt:__sub(b) return P.new(function(...) return eval(self, ...) - eval(b, ...) end) end
function P_mt:__mul(b) return P.new(function(...) return eval(self, ...) * eval(b, ...) end) end
function P_mt:__div(b) return P.new(function(...) return eval(self, ...) / eval(b, ...) end) end
function P_mt:__mod(b) return P.new(function(...) return eval(self, ...) % eval(b, ...) end) end
function P_mt:__pow(b) return P.new(function(...) return eval(self, ...) ^ eval(b, ...) end) end
function P_mt:__concat(b) return P.new(function(...) return eval(self, ...) .. eval(b, ...) end) end
function P_mt:__unm() return P.new(function(...) return -eval(self, ...) end) end

-- __len 仅在 Lua 5.2+ 有效，5.1/JIT 会忽略此方法用于 Table
function P_mt:__len() return P.new(function(...) return #eval(self, ...) end) end

-- 比较操作符
function P_mt:__eq(b) return P.new(function(...) return eval(self, ...) == eval(b, ...) end) end
function P_mt:__lt(b) return P.new(function(...) return eval(self, ...) < eval(b, ...) end) end
function P_mt:__le(b) return P.new(function(...) return eval(self, ...) <= eval(b, ...) end) end

-- 显式比较函数 (Lua 5.1/JIT 兼容方案)
function P.Eq(a, b) return P.new(function(...) return eval(a, ...) == eval(b, ...) end) end
function P.Ne(a, b) return P.new(function(...) return eval(a, ...) ~= eval(b, ...) end) end
function P.Lt(a, b) return P.new(function(...) return eval(a, ...) <  eval(b, ...) end) end
function P.Le(a, b) return P.new(function(...) return eval(a, ...) <= eval(b, ...) end) end
function P.Gt(a, b) return P.new(function(...) return eval(a, ...) >  eval(b, ...) end) end
function P.Ge(a, b) return P.new(function(...) return eval(a, ...) >= eval(b, ...) end) end

-- 调用占位符本身
function P_mt:__call(...) 
    if self._fn then 
        return self._fn(...) 
    end 
    return nil 
end

-- 构造器
function P.new(fn) 
    return setmetatable({ _fn = fn }, P_mt) 
end

-- 编译/提取函数
function P.compile(expr)
    if type(expr) == "function" then return expr end
    if is_P(expr) then
        return expr._fn
    end
    return function() return expr end
end

-- 逻辑非
function P.Not(expr)
    return P.new(function(...) return not eval(expr, ...) end)
end

-- [新增] 长度函数 (替代 # 操作符)
function P.Len(expr)
    return P.new(function(...) return #eval(expr, ...) end)
end

-- 标准占位符
local _1 = P.new(function(...) return select(1, ...) end)
local _2 = P.new(function(...) return select(2, ...) end)
local _3 = P.new(function(...) return select(3, ...) end)
local _4 = P.new(function(...) return select(4, ...) end)
local _5 = P.new(function(...) return select(5, ...) end)

return { 
    _1 = _1, _2 = _2, _3 = _3, _4 = _4, _5 = _5, 
    P = P,
    Not = P.Not,
    Len = P.Len, -- 导出 Len
    -- 导出比较函数
    Eq = P.Eq, Ne = P.Ne, Lt = P.Lt, Le = P.Le, Gt = P.Gt, Ge = P.Ge
}