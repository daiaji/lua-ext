return setmetatable({}, {
    __call = function(_, s, t)
        -- 简单的 ${key} 替换
        return (s:gsub("%$%{(.-)%}", function(k)
            return tostring(t[k] or "")
        end))
    end
})