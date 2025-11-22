local io = require 'ext.io'
local str = require 'ext.string'
local tbl = require 'ext.table'

local M = {}

-- 处理 CSV 行解析，支持引号
local function parse_line(line, sep)
    local res = {}
    local pos = 1
    sep = sep or ','
    while true do
        local c = string.sub(line, pos, pos)
        if c == "" then break end
        
        if c == '"' then
            -- quoted value
            local txt = ""
            pos = pos + 1
            local startp = pos
            while true do
                local nextq = string.find(line, '"', pos)
                if not nextq then 
                    -- quote 未闭合，读取到行尾
                    txt = txt .. string.sub(line, startp)
                    pos = #line + 1
                    break 
                end
                txt = txt .. string.sub(line, startp, nextq - 1)
                pos = nextq + 1
                if string.sub(line, pos, pos) == '"' then
                    -- 双引号转义处理 "" -> "
                    txt = txt .. '"'
                    pos = pos + 1
                    startp = pos
                else
                    break
                end
            end
            table.insert(res, txt)
            -- 跳过分隔符
            local nextc = string.sub(line, pos, pos)
            if nextc == sep then pos = pos + 1 end
        else
            -- simple value
            local nextsep = string.find(line, sep, pos)
            if nextsep then
                table.insert(res, string.sub(line, pos, nextsep - 1))
                pos = nextsep + 1
            else
                table.insert(res, string.sub(line, pos))
                break
            end
        end
    end
    return res
end

function M.read(file, sep)
    sep = sep or ","
    local content = io.readfile(file)
    if not content then return nil, "File not found" end
    
    -- 统一换行符
    content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = str.split(content, "\n")
    if #lines == 0 then return tbl() end
    
    -- 移除空行
    local valid_lines = tbl()
    for _, l in ipairs(lines) do
        if str.trim(l) ~= "" then valid_lines:insert(l) end
    end
    
    if #valid_lines == 0 then return tbl() end

    -- 假设第一行为标题
    local head_line = valid_lines[1]
    local head = parse_line(head_line, sep)
    local data = tbl()
    
    for i = 2, #valid_lines do
        local l = valid_lines[i]
        local row = {}
        local vals = parse_line(l, sep)
        for j, k in ipairs(head) do
            local v = vals[j] or ""
            row[str.trim(k)] = str.trim(v)
        end
        data:insert(row)
    end
    return data
end

return M