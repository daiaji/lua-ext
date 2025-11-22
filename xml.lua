local table = require 'ext.table'
local string = require 'ext.string'
local class = require 'ext.class'

local M = {}
local Doc = class()

function Doc:init(tag, attr)
    self.tag = tag
    self.attr = attr or {}
    self.children = table()
end

function Doc:add_child(child)
    self.children:insert(child)
    return self
end

function Doc:__tostring()
    return M.tostring(self)
end

-- 创建元素节点的快捷方式
function M.elem(tag, items)
    local node = Doc(tag)
    if type(items) == 'table' then
        for k, v in pairs(items) do
            if type(k) == 'number' then
                node:add_child(v)
            else
                node.attr[k] = v
            end
        end
    elseif type(items) == 'string' then
        node:add_child(items)
    end
    return node
end

-- 递归生成 XML 字符串
function M.tostring(doc, indent, level)
    indent = indent or "  "
    level = level or 0
    local prefix = string.rep(indent, level)
    local buf = table()
    
    if type(doc) == 'string' then
        return prefix .. doc
    end
    
    buf:insert(prefix .. "<" .. doc.tag)
    for k, v in pairs(doc.attr) do
        buf:insert(string.format(' %s="%s"', k, tostring(v)))
    end
    
    if #doc.children == 0 then
        buf:insert("/>")
    else
        buf:insert(">")
        local has_tag_child = false
        for _, child in ipairs(doc.children) do
            if type(child) == 'table' then has_tag_child = true end
        end
        
        if has_tag_child then
            buf:insert("\n")
            for _, child in ipairs(doc.children) do
                buf:insert(M.tostring(child, indent, level + 1))
                buf:insert("\n")
            end
            buf:insert(prefix .. "</" .. doc.tag .. ">")
        else
            -- 纯文本子节点不换行
            for _, child in ipairs(doc.children) do
                buf:insert(tostring(child))
            end
            buf:insert("</" .. doc.tag .. ">")
        end
    end
    
    return buf:concat()
end

local function parse_attrs(s)
    local attr = {}
    -- 匹配 key="value"
    for k, v in s:gmatch('([%w:%-_]+)%s*=%s*"(.-)"') do 
        attr[k] = v 
    end
    -- 匹配 key='value'
    for k, v in s:gmatch("([%w:%-_]+)%s*=%s*'(.-)'") do 
        attr[k] = v 
    end
    return attr
end

-- 简易解析器 (非验证性)
function M.parse(s)
    local stack = { { children = table() } }
    local top = stack[1]
    local i = 1
    
    while true do
        -- 查找下一个 <... >
        local ni, nj, closing, label, attr_str, empty = string.find(s, "<(%/?)([%w:%-_]+)(.-)(%/?)>", i)
        if not ni then break end
        
        -- 处理标签前的文本
        local text = string.sub(s, i, ni-1)
        if not string.find(text, "^%s*$") then
            top.children:insert(text)
        end
        
        local attrs = parse_attrs(attr_str)

        if empty == "/" then
            -- 自闭合标签 <tag />
            local node = Doc(label, attrs)
            top.children:insert(node)
        elseif closing == "/" then
            -- 结束标签 </tag>
            if stack[#stack].tag == label then
                table.remove(stack)
                top = stack[#stack]
            else
                -- 标签不匹配或嵌套错误，简易解析器选择忽略
            end
        else
            -- 开始标签 <tag>
            local node = Doc(label, attrs)
            top.children:insert(node)
            table.insert(stack, node)
            top = node
        end
        i = nj + 1
    end
    
    -- 正常情况下 stack[1] 是个虚拟根，它的第一个子节点是真正的文档根
    return stack[1].children[1]
end

return M