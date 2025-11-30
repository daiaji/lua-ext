--[[
Lua 5.3 string.pack/unpack implementation using LuaJIT FFI
Follows Lua 5.3 format specifications.
--]]

local ffi = require 'ffi'
local bit = require 'bit'

local M = {}

-- Native endianness
local native_endian = ffi.abi("le") and "<" or ">"

-- Alignment lookup (defaults, can be adjusted if needed)
local align_map = {
    b = 1, B = 1,
    h = 2, H = 2,
    l = 4, L = 4,
    j = 8, J = 8,
    T = ffi.sizeof("size_t"),
    i = 4, I = 4,
    f = 4, d = 8, n = 8,
    x = 1, c = 1, z = 1, s = 1
}

local function get_int_type(size, signed)
    if size == 1 then return signed and "int8_t" or "uint8_t" end
    if size == 2 then return signed and "int16_t" or "uint16_t" end
    if size == 4 then return signed and "int32_t" or "uint32_t" end
    if size == 8 then return signed and "int64_t" or "uint64_t" end
    return nil
end

local function bswap_ptr(ptr, size)
    if size == 2 then
        local u = ffi.cast("uint16_t*", ptr)
        u[0] = bit.bswap(u[0]) -- bswap for 16 is usually rshift/lshift, bit.bswap is 32. 
        -- LuaJIT bit.bswap is for 32-bit.
        -- Manual swap for 16:
        u[0] = bit.bor(bit.rshift(u[0], 8), bit.lshift(bit.band(u[0], 0xFF), 8))
    elseif size == 4 then
        local u = ffi.cast("uint32_t*", ptr)
        u[0] = bit.bswap(u[0])
    elseif size == 8 then
        local u = ffi.cast("uint64_t*", ptr)
        u[0] = bit.bswap(u[0])
    end
end

-- Iterator for parsing format string
local function fmt_iter(fmt)
    local i = 1
    local len = #fmt
    return function()
        if i > len then return nil end
        local opt = fmt:sub(i, i)
        i = i + 1
        -- Parse optional size/count
        local num_str = fmt:match("^%d+", i)
        local num = nil
        if num_str then
            num = tonumber(num_str)
            i = i + #num_str
        end
        return opt, num
    end
end

local function align_offset(offset, align)
    if align > 1 then
        local rem = offset % align
        if rem ~= 0 then
            return offset + (align - rem)
        end
    end
    return offset
end

function M.packsize(fmt)
    local size = 0
    local endian = native_endian
    local max_align = 1
    
    local iter = fmt_iter(fmt)
    local opt, num
    while true do
        opt, num = iter()
        if not opt then break end
        
        if opt == '<' then endian = '<'
        elseif opt == '>' then endian = '>'
        elseif opt == '=' then endian = native_endian
        elseif opt == '!' then max_align = num or 4 -- Default max align 4? Lua manual says native.
        else
            local a = align_map[opt] or 1
            if a > max_align then a = max_align end
            size = align_offset(size, a)
            
            if opt == 'b' or opt == 'B' then size = size + 1
            elseif opt == 'h' or opt == 'H' then size = size + 2
            elseif opt == 'l' or opt == 'L' then size = size + 8 -- Lua 5.3 'l' is integer (usually 64-bit on 64-bit systems, but strictly 4 bytes in some C packed structs? Lua spec says 'long')
            -- Actually Lua 5.3 spec: l is signed long (native size). j is lua_Integer.
            -- To remain simple we assume 'l' is 8 bytes on 64-bit systems, 4 on 32-bit.
            -- But LuaJIT is often 32-bit or 64-bit. ffi.sizeof("long") is safer.
                size = size + ffi.sizeof("long")
            elseif opt == 'j' or opt == 'J' then size = size + ffi.sizeof("int64_t") -- lua_Integer
            elseif opt == 'T' then size = size + ffi.sizeof("size_t")
            elseif opt == 'i' or opt == 'I' then size = size + (num or ffi.sizeof("int"))
            elseif opt == 'f' then size = size + 4
            elseif opt == 'd' then size = size + 8
            elseif opt == 'n' then size = size + 8 -- lua_Number (double)
            elseif opt == 'x' then size = size + 1
            elseif opt == 'c' then size = size + (num or 0)
            elseif opt == 'z' or opt == 's' then 
                error("string.packsize: variable length format not supported")
            elseif opt == 'X' then
                -- align next
                -- This requires lookahead or strict alignment handling which implies padding size is variable. 
                -- 'X' adds padding. size = align_offset(size, num)
                -- Actually X(n) aligns the *total structure size*? No, it aligns the *next* item.
                -- Lua manual: "aligns the data according to option ! (for native alignment) or !n (for forced alignment)"
                -- Xn adds padding to align to n.
                size = align_offset(size, num or max_align)
            end
        end
    end
    return size
end

function M.pack(fmt, ...)
    local args = {...}
    local arg_idx = 1
    
    -- Two pass: calculate size first, then write
    -- We can't use M.packsize easily for dynamic strings (z, s)
    
    local endian = native_endian
    local max_align = 1
    local size = 0
    
    -- Pass 1: Calculate Size
    local iter = fmt_iter(fmt)
    local opt, num
    while true do
        opt, num = iter()
        if not opt then break end
        
        if opt == '<' or opt == '>' or opt == '=' then 
            -- endian change, no size
        elseif opt == '!' then 
            max_align = num or ffi.alignof(ffi.new("struct { char c; double d; }")) -- guess native max?
        elseif opt == 'x' then
            size = size + 1
        elseif opt == 'X' then
            size = align_offset(size, num or max_align)
        elseif opt == 'z' then
            local s = args[arg_idx] or ""
            arg_idx = arg_idx + 1
            size = size + #s + 1
        elseif opt == 'c' then
            local len = num or 0
            arg_idx = arg_idx + 1 -- consume arg even if fixed size
            size = size + len
        elseif opt == 's' then
            local prefix_len = num or ffi.sizeof("size_t")
            local s = args[arg_idx] or ""
            arg_idx = arg_idx + 1
            size = align_offset(size, prefix_len) -- align the length prefix?
            size = size + prefix_len + #s
        else
            -- Fixed types
            local a = 1
            local item_size = 0
            if opt == 'b' or opt == 'B' then item_size = 1
            elseif opt == 'h' or opt == 'H' then item_size = 2; a = 2
            elseif opt == 'l' or opt == 'L' then item_size = ffi.sizeof("long"); a = item_size
            elseif opt == 'j' or opt == 'J' then item_size = 8; a = 8
            elseif opt == 'T' then item_size = ffi.sizeof("size_t"); a = item_size
            elseif opt == 'i' or opt == 'I' then item_size = num or ffi.sizeof("int"); a = item_size
            elseif opt == 'f' then item_size = 4; a = 4
            elseif opt == 'd' then item_size = 8; a = 8
            elseif opt == 'n' then item_size = 8; a = 8
            end
            
            if a > max_align then a = max_align end
            size = align_offset(size, a)
            size = size + item_size
            if opt ~= 'x' then arg_idx = arg_idx + 1 end
        end
    end
    
    -- Allocate
    local buf = ffi.new("uint8_t[?]", size)
    local offset = 0
    
    -- Pass 2: Write
    arg_idx = 1
    endian = native_endian
    max_align = 1 -- reset
    iter = fmt_iter(fmt) -- reset iterator
    
    while true do
        opt, num = iter()
        if not opt then break end
        
        if opt == '<' then endian = '<'
        elseif opt == '>' then endian = '>'
        elseif opt == '=' then endian = native_endian
        elseif opt == '!' then max_align = num or ffi.alignof(ffi.new("struct { char c; double d; }"))
        elseif opt == 'x' then
            buf[offset] = 0
            offset = offset + 1
        elseif opt == 'X' then
            local aligned = align_offset(offset, num or max_align)
            while offset < aligned do
                buf[offset] = 0
                offset = offset + 1
            end
        elseif opt == 'z' then
            local s = tostring(args[arg_idx])
            arg_idx = arg_idx + 1
            ffi.copy(buf + offset, s, #s)
            offset = offset + #s
            buf[offset] = 0
            offset = offset + 1
        elseif opt == 'c' then
            local s = tostring(args[arg_idx])
            arg_idx = arg_idx + 1
            local len = num or 0
            if #s > len then s = s:sub(1, len) end
            ffi.copy(buf + offset, s, #s)
            -- padding
            if #s < len then
                ffi.fill(buf + offset + #s, len - #s, 0)
            end
            offset = offset + len
        elseif opt == 's' then
            local prefix_len = num or ffi.sizeof("size_t")
            local s = tostring(args[arg_idx])
            arg_idx = arg_idx + 1
            
            -- Align prefix
            local a = prefix_len
            if a > max_align then a = max_align end
            local aligned = align_offset(offset, a)
            while offset < aligned do buf[offset] = 0; offset = offset + 1 end
            
            -- Write length
            local ctype = get_int_type(prefix_len, false)
            if not ctype then error("invalid string length prefix size") end
            local ptr = ffi.cast(ctype.."*", buf + offset)
            ptr[0] = #s
            if endian ~= native_endian then bswap_ptr(ptr, prefix_len) end
            offset = offset + prefix_len
            
            -- Write string
            ffi.copy(buf + offset, s, #s)
            offset = offset + #s
        else
            -- Integers/Floats
            local val = args[arg_idx]
            arg_idx = arg_idx + 1
            
            local item_size = 0
            local ctype = nil
            local a = 1
            
            if opt == 'b' then item_size=1; ctype="int8_t"
            elseif opt == 'B' then item_size=1; ctype="uint8_t"
            elseif opt == 'h' then item_size=2; ctype="int16_t"; a=2
            elseif opt == 'H' then item_size=2; ctype="uint16_t"; a=2
            elseif opt == 'l' then item_size=ffi.sizeof("long"); ctype="int64_t"; a=item_size -- approx
            elseif opt == 'L' then item_size=ffi.sizeof("long"); ctype="uint64_t"; a=item_size -- approx
            elseif opt == 'j' then item_size=8; ctype="int64_t"; a=8
            elseif opt == 'J' then item_size=8; ctype="uint64_t"; a=8
            elseif opt == 'T' then item_size=ffi.sizeof("size_t"); ctype="uint64_t"; a=item_size
            elseif opt == 'i' or opt == 'I' then 
                item_size = num or ffi.sizeof("int")
                ctype = (opt=='i' and "int" or "uint") .. (item_size*8) .. "_t"
                a = item_size
            elseif opt == 'f' then item_size=4; ctype="float"; a=4
            elseif opt == 'd' or opt == 'n' then item_size=8; ctype="double"; a=8
            end
            
            if a > max_align then a = max_align end
            local aligned = align_offset(offset, a)
            while offset < aligned do buf[offset] = 0; offset = offset + 1 end
            
            if ctype then
                local ptr = ffi.cast(ctype.."*", buf + offset)
                ptr[0] = val
                if endian ~= native_endian and item_size > 1 then
                    bswap_ptr(ptr, item_size)
                end
                offset = offset + item_size
            end
        end
    end
    
    return ffi.string(buf, size)
end

function M.unpack(fmt, s, pos)
    pos = pos or 1
    local ptr = ffi.cast("const uint8_t*", s)
    local len = #s
    -- FFI uses 0-based indexing, Lua 1-based.
    -- s is a Lua string, but ptr allows access.
    -- ptr[0] is s:byte(1).
    -- So ptr[pos-1] is current byte.
    local cursor = pos - 1
    
    local res = {}
    local endian = native_endian
    local max_align = 1
    
    local iter = fmt_iter(fmt)
    local opt, num
    
    while true do
        opt, num = iter()
        if not opt then break end
        
        if opt == '<' then endian = '<'
        elseif opt == '>' then endian = '>'
        elseif opt == '=' then endian = native_endian
        elseif opt == '!' then max_align = num or ffi.alignof(ffi.new("struct { char c; double d; }"))
        elseif opt == 'x' then
            cursor = cursor + 1
        elseif opt == 'X' then
            cursor = align_offset(cursor, num or max_align)
        elseif opt == 'z' then
            local start = cursor
            while cursor < len and ptr[cursor] ~= 0 do
                cursor = cursor + 1
            end
            if cursor >= len and ptr[len-1] ~= 0 then error("unfinished string") end
            local str = ffi.string(ptr + start, cursor - start)
            table.insert(res, str)
            cursor = cursor + 1 -- skip zero
        elseif opt == 'c' then
            local slen = num or 0
            if cursor + slen > len then error("data string too short") end
            table.insert(res, ffi.string(ptr + cursor, slen))
            cursor = cursor + slen
        elseif opt == 's' then
            local prefix_len = num or ffi.sizeof("size_t")
            local a = prefix_len
            if a > max_align then a = max_align end
            cursor = align_offset(cursor, a)
            
            if cursor + prefix_len > len then error("data string too short") end
            
            local ctype = get_int_type(prefix_len, false)
            local slen
            
            -- We need to copy to align/read safely if unaligned access isn't safe?
            -- x86 handles unaligned, others might not.
            -- Safe way: copy to temp
            local tmp = ffi.new(ctype.."[1]")
            ffi.copy(tmp, ptr + cursor, prefix_len)
            if endian ~= native_endian then bswap_ptr(tmp, prefix_len) end
            slen = tonumber(tmp[0])
            cursor = cursor + prefix_len
            
            if cursor + slen > len then error("data string too short") end
            table.insert(res, ffi.string(ptr + cursor, slen))
            cursor = cursor + slen
        else
            local item_size = 0
            local ctype = nil
            local a = 1
            local is_signed = false
            local is_float = false
            
            if opt == 'b' then item_size=1; ctype="int8_t"; is_signed=true
            elseif opt == 'B' then item_size=1; ctype="uint8_t"
            elseif opt == 'h' then item_size=2; ctype="int16_t"; a=2; is_signed=true
            elseif opt == 'H' then item_size=2; ctype="uint16_t"; a=2
            elseif opt == 'l' then item_size=ffi.sizeof("long"); ctype="int64_t"; a=item_size; is_signed=true
            elseif opt == 'L' then item_size=ffi.sizeof("long"); ctype="uint64_t"; a=item_size
            elseif opt == 'j' then item_size=8; ctype="int64_t"; a=8; is_signed=true
            elseif opt == 'J' then item_size=8; ctype="uint64_t"; a=8
            elseif opt == 'T' then item_size=ffi.sizeof("size_t"); ctype="uint64_t"; a=item_size
            elseif opt == 'i' or opt == 'I' then 
                item_size = num or ffi.sizeof("int")
                is_signed = (opt == 'i')
                ctype = (is_signed and "int" or "uint") .. (item_size*8) .. "_t"
                a = item_size
            elseif opt == 'f' then item_size=4; ctype="float"; a=4; is_float=true
            elseif opt == 'd' or opt == 'n' then item_size=8; ctype="double"; a=8; is_float=true
            end
            
            if ctype then
                if a > max_align then a = max_align end
                cursor = align_offset(cursor, a)
                if cursor + item_size > len then error("data string too short") end
                
                -- Copy to temp buffer to handle alignment and endian swap safely
                -- (and casting pointers directly into string buffer might be unsafe if string is moved/gc'd? 
                -- actually ffi.cast on lua string keeps string anchored? No.
                -- But 's' is passed to function, so it's anchored on stack. 'ptr' is derived from it.)
                -- However, strict alignment archs (ARM) fail if we cast random char* to int*.
                
                -- Optimization: use a union or just ffi.new
                local tmp
                if is_float then
                    tmp = ffi.new(ctype.."[1]")
                else
                    tmp = ffi.new(ctype.."[1]")
                end
                
                ffi.copy(tmp, ptr + cursor, item_size)
                
                if endian ~= native_endian and item_size > 1 then
                    -- For floats, we treat as int bits for swapping
                    if is_float then
                        local raw_type = (item_size == 4) and "uint32_t" or "uint64_t"
                        local raw_ptr = ffi.cast(raw_type.."*", tmp)
                        bswap_ptr(raw_ptr, item_size)
                    else
                        bswap_ptr(tmp, item_size)
                    end
                end
                
                table.insert(res, tmp[0])
                cursor = cursor + item_size
            end
        end
    end
    
    return cursor + 1, unpack(res)
end

return M