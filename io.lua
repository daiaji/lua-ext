local io = {}
for k, v in pairs(require 'io') do io[k] = v end

-- [Modified] Use lfs_ffi for Unicode support on Windows (and Linux consistency)
local has_lfs, lfs = pcall(require, 'lfs_ffi')

-- [Added] Helper: Windows encoding conversion logic
local win_convert = nil
local ffi = require 'ffi'
if ffi.os == 'Windows' then
    pcall(function()
        local k32 = require 'ffi.req' 'Windows.sdk.kernel32'
        local CP_ACP = 0
        local CP_UTF8 = 65001
        
        local function w2u(ptr, len)
            if not ptr then return "" end
            -- len is wide char count
            local bytes = k32.WideCharToMultiByte(CP_UTF8, 0, ptr, len, nil, 0, nil, nil)
            if bytes <= 0 then return "" end
            local buf = ffi.new("char[?]", bytes)
            k32.WideCharToMultiByte(CP_UTF8, 0, ptr, len, buf, bytes, nil, nil)
            return ffi.string(buf, bytes)
        end
        
        local function a2u(ptr, len)
            -- ANSI -> Wide -> UTF8
            local wlen = k32.MultiByteToWideChar(CP_ACP, 0, ptr, len, nil, 0)
            local wbuf = ffi.new("wchar_t[?]", wlen)
            k32.MultiByteToWideChar(CP_ACP, 0, ptr, len, wbuf, wlen)
            return w2u(wbuf, wlen)
        end

        win_convert = { w2u = w2u, a2u = a2u }
    end)
end

function io.readfile(fn, options)
    -- [Modified] Enhanced readfile with options for encoding
    local mode = 'rb'
    local f, err
    
    if has_lfs and lfs.fopen then
        f, err = lfs.fopen(fn, mode)
    else
        f, err = io.open(fn, mode)
    end
    
    if not f then return false, err end

    local d = f:read('*a')
    f:close()
    
    if not d then return nil, "read failed" end

    -- [Added] Encoding handling
    if type(options) == 'table' then
        local len = #d
        local encoding = options.encoding or 'auto'
        local content = d
        
        if win_convert then
            local ptr = ffi.cast("const uint8_t*", d)
            
            if encoding == 'auto' then
                if len >= 3 and ptr[0]==0xEF and ptr[1]==0xBB and ptr[2]==0xBF then
                    -- UTF-8 BOM
                    content = ffi.string(ptr + 3, len - 3)
                elseif len >= 2 and ptr[0]==0xFF and ptr[1]==0xFE then
                    -- UTF-16 LE
                    content = win_convert.w2u(ffi.cast("const wchar_t*", ptr + 2), (len - 2) / 2)
                else
                    -- Assume ANSI
                    content = win_convert.a2u(ffi.cast("const char*", ptr), len)
                end
            elseif encoding == 'utf16' then
                content = win_convert.w2u(ffi.cast("const wchar_t*", ptr), len / 2)
            elseif encoding == 'ansi' then
                content = win_convert.a2u(ffi.cast("const char*", ptr), len)
            end
            
            -- Normalize line endings
            if content then
                content = content:gsub("\r\n", "\n")
            end
            return content
        end
    end

    return d
end

function io.writefile(fn, d)
	if has_lfs and lfs.fopen then
		local f, err = lfs.fopen(fn, 'wb')
		if not f then return false, err end
		if d then f:write(d) end
		f:close()
		return true
	else
		local f, err = io.open(fn, 'wb')
		if not f then return false, err end
		if d then f:write(d) end
		f:close()
		return true
	end
end

function io.appendfile(fn, d)
	if has_lfs and lfs.fopen then
		local f, err = lfs.fopen(fn, 'ab')
		if not f then return false, err end
		if d then f:write(d) end
		f:close()
		return true
	else
		local f, err = io.open(fn, 'ab')
		if not f then return false, err end
		if d then f:write(d) end
		f:close()
		return true
	end
end

if has_lfs and lfs.fopen then
	local original_lines = io.lines
	function io.lines(filename, ...)
		if filename == nil then
			return original_lines(...)
		end
		local f, err = lfs.fopen(filename, 'r')
		if not f then error(err) end

		local args = { ... }
		local unpack = table.unpack or unpack
		return function()
			local res = f:read(unpack(args))
			if not res then
				f:close()
				return nil
			end
			return res
		end
	end
end

function io.readproc(cmd)
	local f, err = io.popen(cmd)
	if not f then return false, err end
	local d = f:read('*a')
	f:close()
	return d
end

function io.getfiledir(fn)
	local dir, name = fn:match '^(.*)[/\\]([^/\\]-)$'
	if dir == '' then
		if name == '' then return '/', '/' end
		return '/', name
	elseif not dir then
		return '.', fn
	end
	return dir, name
end

function io.getfileext(fn)
	local front, ext = fn:match('^(.*)%.([^%./\\]-)$')
	if front then
		return front, ext
	end
	return fn, nil
end

do
	local detect_lfs = require 'ext.detect_lfs'
	local lfs = detect_lfs()
	if lfs then
		local filemeta = debug.getmetatable(io.stdout)
		filemeta.lock = lfs.lock
		filemeta.unlock = lfs.unlock
	end
end

local ffi = require 'ffi'
local PopenMeta 

if ffi.os == 'Windows' and lfs then
	local kernel32 = require 'ffi.req' 'Windows.sdk.kernel32'
	local C = ffi.C
	local CP_UTF8 = 65001

	local function to_wide(str)
		if not str then return nil end
		local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
		if len == 0 then return nil end
		local buf = ffi.new("wchar_t[?]", len)
		kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
		return buf
	end

	ffi.cdef[[
		typedef struct _iobuf FILE;
		FILE* _wpopen(const wchar_t* command, const wchar_t* mode);
		int _pclose(FILE* stream);
	]]

	PopenMeta = {
		__index = {},
		__gc = function(self) self:close() end
	}

	function PopenMeta.__index:read(...)
		if lfs.FileHandle and lfs.FileHandle.read then
			return lfs.FileHandle.read(self, ...)
		end
		return nil, "FileHandle.read not available"
	end

	function PopenMeta.__index:lines(...)
		return io.lines(self, ...)
	end

	function PopenMeta.__index:close()
		if self.fp then
			local ret = C._pclose(self.fp)
			self.fp = nil
			return true, "exit", ret
		end
		return nil, "already closed"
	end

	function io.popen(cmd, mode)
		mode = mode or 'r'
		local wcmd = to_wide(cmd)
		local wmode = to_wide(mode)
		local fp = C._wpopen(wcmd, wmode)

		if fp == nil then return nil, "popen failed" end

		return setmetatable({ fp = fp }, PopenMeta)
	end
end

if ffi.os == 'Windows' and has_lfs then
	local original_io_open = io.open
	local original_io_input = io.input
	local original_io_output = io.output
	local original_io_read = io.read
	local original_io_write = io.write
	local original_io_flush = io.flush
	local original_io_close = io.close
	local original_io_type = io.type
	local original_io_tmpfile = io.tmpfile

	local current_input = io.stdin
	local current_output = io.stdout

	local function is_custom_handle(obj)
		local mt = getmetatable(obj)
		return (lfs.FileHandle and mt == lfs.FileHandle) or (PopenMeta and mt == PopenMeta)
	end

	function io.open(path, mode)
		return lfs.fopen(path, mode)
	end
	
	io.wopen = io.open

	function io.type(obj)
		if is_custom_handle(obj) then
			return obj.fp and "file" or "closed file"
		end
		return original_io_type(obj)
	end

	function io.tmpfile()
		local name = os.tmpname()
		if not name then return nil, "unable to generate tmp name" end
		return io.open(name, "w+bD")
	end

	function io.input(file)
		if file then
			if type(file) == 'string' then
				local f, err = io.open(file, "r")
				if not f then error(err) end
				current_input = f
			else
				current_input = file
			end
			return current_input
		else
			return current_input
		end
	end

	function io.output(file)
		if file then
			if type(file) == 'string' then
				local f, err = io.open(file, "w")
				if not f then error(err) end
				current_output = f
			else
				current_output = file
			end
			return current_output
		else
			return current_output
		end
	end

	function io.read(...)
		if is_custom_handle(current_input) then
			return current_input:read(...)
		else
			if type(current_input) == 'userdata' then
				return current_input:read(...)
			else
				return original_io_read(...)
			end
		end
	end

	function io.write(...)
		if is_custom_handle(current_output) then
			return current_output:write(...)
		else
			if type(current_output) == 'userdata' then
				return current_output:write(...)
			else
				return original_io_write(...)
			end
		end
	end

	function io.flush()
		if is_custom_handle(current_output) then
			return current_output:flush()
		else
			if type(current_output) == 'userdata' then
				return current_output:flush()
			else
				return original_io_flush()
			end
		end
	end

	function io.close(file)
		file = file or current_output
		if is_custom_handle(file) then
			return file:close()
		else
			return original_io_close(file)
		end
	end
end

return io