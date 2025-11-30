local ffi = require 'ffi'
local bit = require 'bit'

local M = {}

local BufferMethods = {}
BufferMethods.__index = BufferMethods

function BufferMethods:ptr(offset) 
    return self.data + (offset or 0) 
end

function BufferMethods:read(offset, type_str)
    local ptr = self.data + (offset or 0)
    if type_str == "int8" then return ffi.cast("int8_t*", ptr)[0]
    elseif type_str == "uint8" or type_str == "byte" then return ptr[0]
    elseif type_str == "int16" then return ffi.cast("int16_t*", ptr)[0]
    elseif type_str == "uint16" then return ffi.cast("uint16_t*", ptr)[0]
    elseif type_str == "int32" or type_str == "int" then return ffi.cast("int32_t*", ptr)[0]
    elseif type_str == "uint32" or type_str == "uint" then return ffi.cast("uint32_t*", ptr)[0]
    elseif type_str == "int64" then return ffi.cast("int64_t*", ptr)[0]
    elseif type_str == "uint64" then return ffi.cast("uint64_t*", ptr)[0]
    elseif type_str == "float" then return ffi.cast("float*", ptr)[0]
    elseif type_str == "double" then return ffi.cast("double*", ptr)[0]
    elseif type_str == "ptr" then return ffi.cast("void**", ptr)[0]
    else error("Unknown type: " .. tostring(type_str)) end
end

function BufferMethods:write(offset, val, type_str)
    local ptr = self.data + (offset or 0)
    if type_str == "int8" then ffi.cast("int8_t*", ptr)[0] = val
    elseif type_str == "uint8" or type_str == "byte" then ptr[0] = val
    elseif type_str == "int16" then ffi.cast("int16_t*", ptr)[0] = val
    elseif type_str == "uint16" then ffi.cast("uint16_t*", ptr)[0] = val
    elseif type_str == "int32" or type_str == "int" then ffi.cast("int32_t*", ptr)[0] = val
    elseif type_str == "uint32" or type_str == "uint" then ffi.cast("uint32_t*", ptr)[0] = val
    elseif type_str == "int64" then ffi.cast("int64_t*", ptr)[0] = val
    elseif type_str == "uint64" then ffi.cast("uint64_t*", ptr)[0] = val
    elseif type_str == "float" then ffi.cast("float*", ptr)[0] = val
    elseif type_str == "double" then ffi.cast("double*", ptr)[0] = val
    elseif type_str == "ptr" then ffi.cast("void**", ptr)[0] = ffi.cast("void*", val)
    else error("Unknown type: " .. tostring(type_str)) end
    return self
end

-- 定义结构体，使用变长数组
ffi.cdef[[
typedef struct { size_t len; uint8_t data[?]; } ExtBuffer;
]]
local ExtBuffer = ffi.metatype("ExtBuffer", BufferMethods)

function M.alloc(size)
    if size < 0 then error("Invalid size") end
    local buf = ExtBuffer(size)
    buf.len = size
    return buf
end

return M