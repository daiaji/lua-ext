local table = require 'ext.table'
local detect_ffi = require 'ext.detect_ffi'
local ffi = detect_ffi()

local Array2D = {}
Array2D.__index = Array2D

if ffi then
    -- === LuaJIT FFI 高性能模式 ===
    -- 使用连续内存块代替嵌套 table，大幅提升数值计算性能
    
    function Array2D.new(rows, cols, val)
        local len = rows * cols
        -- 使用 VLA (Variable Length Array) 分配连续 double 内存
        -- 默认为 double，适合数值计算。如果是 int 需求可修改此处
        local data = ffi.new("double[?]", len)
        
        -- ffi.new 默认初始化为 0，如果 val 非 0 则需填充
        if val and val ~= 0 then
            for i = 0, len - 1 do 
                data[i] = val 
            end
        end

        local self = {
            _data = data,
            rows = rows,
            cols = cols
        }
        return setmetatable(self, Array2D)
    end

    function Array2D:get(r, c)
        -- 边界检查 (Lua 风格 1-base)
        if r < 1 or r > self.rows or c < 1 or c > self.cols then 
            return nil 
        end
        -- 坐标转换: (row-1)*stride + (col-1)
        return self._data[(r-1) * self.cols + (c-1)]
    end

    function Array2D:set(r, c, val)
        if r < 1 or r > self.rows or c < 1 or c > self.cols then 
            return 
        end
        self._data[(r-1) * self.cols + (c-1)] = val
    end

    function Array2D:column(c)
        local res = table()
        if c < 1 or c > self.cols then return res end
        for r = 1, self.rows do
            -- 直接访问，减少函数调用开销
            res:insert(self._data[(r-1) * self.cols + (c-1)])
        end
        return res
    end

    function Array2D:iter()
        local r, c = 1, 0
        local rows, cols = self.rows, self.cols
        local data = self._data
        -- JIT Friendly Iterator (避免 coroutine)
        return function()
            c = c + 1
            if c > cols then
                c = 1
                r = r + 1
            end
            if r > rows then return nil end
            return r, c, data[(r-1) * cols + (c-1)]
        end
    end
    
else
    -- === 标准 Lua 回退模式 ===
    -- 兼容 PUC Lua 或未启用 FFI 的环境
    
    function Array2D.new(rows, cols, val)
        local res = table()
        for i=1,rows do
            local r = table()
            for j=1,cols do 
                r:insert(val or 0) 
            end
            res:insert(r)
        end
        return setmetatable({_data=res, rows=rows, cols=cols}, Array2D)
    end
    
    function Array2D:get(r, c) 
        local row = self._data[r]
        return row and row[c]
    end
    
    function Array2D:set(r, c, val) 
        local row = self._data[r]
        if row then row[c] = val end
    end
    
    function Array2D:column(c)
        local res = table()
        for r = 1, self.rows do
            res:insert(self:get(r, c))
        end
        return res
    end

    function Array2D:iter()
        local r, c = 1, 0
        local rows, cols = self.rows, self.cols
        return function()
            c = c + 1
            if c > cols then
                c = 1
                r = r + 1
            end
            if r > rows then return nil end
            return r, c, self._data[r][c]
        end
    end
end

-- 通用方法
function Array2D:size()
    return self.rows, self.cols
end

return Array2D