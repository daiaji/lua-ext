local io = require 'ext.io'
local str = require 'ext.string'

local M = {}

-- 读取 INI 风格的配置文件
function M.read(file)
    local s = io.readfile(file)
    if not s then return nil, "Could not read file: " .. tostring(file) end
    
    local res = { _ = {} }
    local sec = res._
    
    -- 处理换行，兼容 Windows/Unix
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    
    local lines = str.split(s, "\n")
    -- [FIX] 使用 ipairs 迭代 table
    for _, l in ipairs(lines) do
        l = l:match("^%s*(.-)%s*$")
        if l ~= "" and not l:find("^[#;]") then
            local sn = l:match("^%[(.-)%]$")
            if sn then
                res[sn] = res[sn] or {}
                sec = res[sn]
            else
                local k, v = l:match("^(.-)%s*=%s*(.*)$")
                if k then
                    if v == "true" then v = true
                    elseif v == "false" then v = false
                    else 
                        local num = tonumber(v)
                        if num then v = num end
                    end
                    sec[k] = v
                end
            end
        end
    end
    return res
end

return M