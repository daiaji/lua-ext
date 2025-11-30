--[[
Lua 5.3 utf8 library implementation using LuaJIT FFI
Acts as a polyfill for Lua 5.1/LuaJIT.
--]]

-- [OPTIMIZATION] Best Practice: Check for native/existing utf8 library first.
-- Lua 5.3+ and some patched LuaJIT environments (like OpenResty) might already have this.
local ok, native_utf8 = pcall(require, "utf8")
if ok and type(native_utf8) == 'table' and native_utf8.offset then
    return native_utf8
end

-- Fallback: FFI Implementation
local ffi = require 'ffi'
local bit = require 'bit'

local M = {}

M.charpattern = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"

-- Helper to get C pointer to string
local function str_ptr(s)
    return ffi.cast("const uint8_t*", s)
end

-- Decode one codepoint at position i (0-based relative to ptr)
-- Returns code, next_i (relative)
local function decode_utf8(ptr, i, len)
    local c = ptr[i]
    if c < 0x80 then
        return c, i + 1
    end
    
    local res = 0
    local seq_len = 0
    
    if bit.band(c, 0xE0) == 0xC0 then
        res = bit.band(c, 0x1F)
        seq_len = 2
    elseif bit.band(c, 0xF0) == 0xE0 then
        res = bit.band(c, 0x0F)
        seq_len = 3
    elseif bit.band(c, 0xF8) == 0xF0 then
        res = bit.band(c, 0x07)
        seq_len = 4
    else
        return nil, "invalid UTF-8 code"
    end
    
    if i + seq_len > len then
        return nil, "invalid UTF-8 code" -- Truncated
    end
    
    for j = 1, seq_len - 1 do
        local b = ptr[i + j]
        if bit.band(b, 0xC0) ~= 0x80 then
            return nil, "invalid UTF-8 code"
        end
        res = bit.bor(bit.lshift(res, 6), bit.band(b, 0x3F))
    end
    
    if res > 0x10FFFF then
        return nil, "value out of range"
    end
    
    return res, i + seq_len
end

function M.char(...)
    local args = {...}
    local buf = {}
    for _, code in ipairs(args) do
        if code < 0 or code > 0x10FFFF then
            error("value out of range")
        end
        
        if code < 0x80 then
            table.insert(buf, string.char(code))
        elseif code < 0x800 then
            table.insert(buf, string.char(
                bit.bor(0xC0, bit.rshift(code, 6)),
                bit.bor(0x80, bit.band(code, 0x3F))
            ))
        elseif code < 0x10000 then
            table.insert(buf, string.char(
                bit.bor(0xE0, bit.rshift(code, 12)),
                bit.bor(0x80, bit.band(bit.rshift(code, 6), 0x3F)),
                bit.bor(0x80, bit.band(code, 0x3F))
            ))
        else
            table.insert(buf, string.char(
                bit.bor(0xF0, bit.rshift(code, 18)),
                bit.bor(0x80, bit.band(bit.rshift(code, 12), 0x3F)),
                bit.bor(0x80, bit.band(bit.rshift(code, 6), 0x3F)),
                bit.bor(0x80, bit.band(code, 0x3F))
            ))
        end
    end
    return table.concat(buf)
end

function M.codes(s)
    local ptr = str_ptr(s)
    local len = #s
    local i = 0
    return function()
        if i >= len then return nil end
        local code, next_i = decode_utf8(ptr, i, len)
        if not code then error(next_i) end
        local pos = i + 1 -- Lua 1-based index
        i = next_i
        return pos, code
    end
end

function M.codepoint(s, i, j)
    i = i or 1
    j = j or i
    if i < 0 then i = #s + i + 1 end
    if j < 0 then j = #s + j + 1 end
    
    local ptr = str_ptr(s)
    local len = #s
    local codes = {}
    
    local curr = i - 1 -- 0-based
    while curr < j do
        if curr >= len then error("bad argument #3 to 'codepoint' (out of range)") end
        local code, next_i = decode_utf8(ptr, curr, len)
        if not code then error(next_i) end
        table.insert(codes, code)
        curr = next_i
    end
    return unpack(codes)
end

function M.len(s, i, j)
    i = i or 1
    j = j or -1
    if i < 0 then i = #s + i + 1 end
    if j < 0 then j = #s + j + 1 end
    
    local ptr = str_ptr(s)
    local len = #s
    local count = 0
    
    local curr = i - 1
    while curr < j do
        if curr >= len then break end
        local code, next_i = decode_utf8(ptr, curr, len)
        if not code then return nil, curr + 1 end
        count = count + 1
        curr = next_i
    end
    return count
end

function M.offset(s, n, i)
    i = i or (n >= 0 and 1 or #s + 1)
    if i < 0 then i = #s + i + 1 end
    
    local ptr = str_ptr(s)
    local len = #s
    local curr = i - 1 -- 0-based
    
    if n == 0 then
        -- Find start of current char
        if curr >= len then return nil end
        while curr > 0 and bit.band(ptr[curr], 0xC0) == 0x80 do
            curr = curr - 1
        end
        return curr + 1
    end
    
    if n > 0 then
        while n > 0 and curr < len do
            local code, next_i = decode_utf8(ptr, curr, len)
            if not code then error(next_i) end
            curr = next_i
            n = n - 1
        end
        if n == 0 then return curr + 1 end
    else
        while n < 0 and curr > 0 do
            -- Move back
            curr = curr - 1
            while curr > 0 and bit.band(ptr[curr], 0xC0) == 0x80 do
                curr = curr - 1
            end
            n = n + 1
        end
        if n == 0 then return curr + 1 end
    end
    
    return nil
end

return M