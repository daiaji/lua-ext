local M = {}
local table = require 'ext.table'

-- 增强型参数解析
-- args: lua 的 arg 表
-- schema: 定义参数规则，例如 { {'verbose', 'v', type='flag'}, {'output', 'o', default='out.txt'} }
function M.parse(args, schema)
    local res = { _rest = table() }
    local map = {} -- 存储 flag -> schema definition 的映射
    
    -- 预处理 schema
    for _, item in ipairs(schema) do
        -- item[1] 是字段名 (key)
        local name = item[1]
        res[name] = item.default
        
        -- [FIX] 自动映射字段名为参数 flag
        -- 长度为1 -> -name, 长度>1 -> --name
        if type(name) == 'string' then
            local auto_flag = (#name == 1 and '-' or '--') .. name
            map[auto_flag] = item
        end
        
        -- 收集显式 aliases (短名和长名)
        for j = 2, #item do
            local flag = item[j]
            -- 自动补充连字符前缀
            if flag:sub(1,1) ~= '-' then
                if #flag == 1 then 
                    flag = '-' .. flag 
                else 
                    flag = '--' .. flag 
                end
            end
            map[flag] = item
        end
    end
    
    local i = 1
    while i <= #args do
        local arg = args[i]
        
        -- 处理 --key=value 格式
        local key, eq_val = arg:match("^([^=]+)=(.*)$")
        if not key then key = arg end

        local d = map[key]
        
        if d then
            if d.type == 'flag' then
                res[d[1]] = true
                -- flag 不需要消费下一个参数
            else
                local val
                if eq_val then
                    val = eq_val
                else
                    -- 读取下一个参数作为值
                    local next_arg = args[i+1]
                    if next_arg then
                        i = i + 1
                        val = next_arg
                    else
                        error("Missing value for argument: " .. arg)
                    end
                end

                if d.type == 'number' then
                    val = tonumber(val) or val
                end
                res[d[1]] = val
            end
        else
            -- 未知参数归入 _rest
            res._rest:insert(arg)
        end
        i = i + 1
    end
    return res
end

return M