local io = {}
for k, v in pairs(require 'io') do io[k] = v end

-- [Modified] Use lfs_ffi for Unicode support on Windows (and Linux consistency)
-- We expect lfs_ffi to support fopen/remove_file/rename_file via FFI
local has_lfs, lfs = pcall(require, 'lfs_ffi')

-- io or os?  io since it is shorthand for io.open():read()
function io.readfile(fn)
	-- [Modified] Try lfs.fopen first for Unicode support
	if has_lfs and lfs.fopen then
		local f, err = lfs.fopen(fn, 'rb')
		if not f then return false, err end
		local d = f:read('*a')
		f:close()
		return d
	else
		local f, err = io.open(fn, 'rb')
		if not f then return false, err end

		-- file.read compat (tested on Windows)
		-- 						*a	a	*l	l
		-- lua-5.3.5:			yes	yes	yes	yes		jit == nil and _VERSION == 'Lua 5.3'
		-- lua-5.2.4:			yes	no	yes	no		jit == nil and _VERSION == 'Lua 5.2'
		-- lua-5.1.5:			yes	no	yes	no		jit == nil and _VERSION == 'Lua 5.1'
		-- luajit-2.1.0-beta3:	yes	yes	yes	yes		(jit.version == 'LuaJIT 2.1.0-beta3' / jit.version_num == 20100)
		-- luajit-2.0.5			yes	no	yes	no		(jit.version == 'LuaJIT 2.0.5' / jit.version_num == 20005)
		local d = f:read('*a')
		f:close()
		return d
	end
end

function io.writefile(fn, d)
	-- [Modified] Try lfs.fopen first
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
	-- [Modified] Try lfs.fopen first
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

-- [Modified] Override io.lines to support Unicode paths via lfs.fopen
if has_lfs and lfs.fopen then
	local original_lines = io.lines
	function io.lines(filename, ...)
		if filename == nil then
			-- [Fix] Lua 5.1/JIT io.lines(nil) throws error, io.lines() reads stdin.
			-- Pass arguments transparently to original implementation.
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
	-- [Fix] support backslash for windows paths
	local dir, name = fn:match '^(.*)[/\\]([^/\\]-)$'
	if dir == '' then
		-- "/" => "/", "/"
		if name == '' then return '/', '/' end
		-- "/x" => "/", "x"
		return '/', name
	elseif not dir then
		return '.', fn
	end
	return dir, name
end

-- this should really return the extension first.
-- that is the function name, after all.
function io.getfileext(fn)
	-- [Fix] exclude backslash from extension match to prevent "dir.v1\file" from matching ".v1\file"
	local front, ext = fn:match('^(.*)%.([^%./\\]-)$')
	if front then
		return front, ext
	end
	-- no ext? then leave that field nil - just return the base filename
	return fn, nil
end

-- in Lua 5.3.5 at least:
-- (for file = getmetatable(io.open(something)))
-- io.read ~= file.read
-- file.__index == file
-- within meta.lua, simply modifying the file metatable
-- but if someone requires ext/io.lua and not lua then io.open and all subsequently created files will need to be modified
--[[ TODO FIXME
if jit or (not jit and _VERSION < 'Lua 5.2') then

	local function fixfilereadargs(...)
		print(...)
		if select('#', ...) == 0 then return ... end
		local fmt = select(1, ...)
		if fmt == 'a' then fmt = '*a'
		elseif fmt == 'l' then fmt = '*l'
		elseif fmt == 'n' then fmt = '*n'
		end
		return fmt, fixfilereadargs(select(2, ...))
	end

	-- even though io.read is basically the same as file.read, they are still different functions
	-- so file.read will still have to be separately overridden
	local oldfileread
	local function newfileread(...)
		return oldfileread(fixfilereadargs(...))
	end
	io.read = function(...)
		return newfileread(io.stdout, ...)
	end

	local oldfilemeta = debug.getmetatable(io.stdout)
	local newfilemeta = {}
	for k,v in pairs(oldfilemeta) do
		newfilemeta[k] = v
	end

	-- override file:read
	oldfileread = oldfilemeta.read
	newfilemeta.read = newfileread

	-- should these be overridden in this case, or only when running ext/meta.lua?
	debug.setmetatable(io.stdin, newfilemeta)
	debug.setmetatable(io.stdout, newfilemeta)
	debug.setmetatable(io.stderr, newfilemeta)

	local function fixfilemeta(...)
		if select('#', ...) > 0 then
			local f = select(1, ...)
			if f then
				debug.setmetatable(f, newfilemeta)
			end
		end
		return ...
	end

	local oldioopen = io.open
	function io.open(...)
		return fixfilemeta(oldioopen(...))
	end
end
--]]

-- [[ add lfs lock/unlock to files
do
	local detect_lfs = require 'ext.detect_lfs'
	local lfs = detect_lfs()
	if lfs then
		-- can I do this? yes on Lua 5.3.  Yes on LuaJIT 2.1.0-beta3
		local filemeta = debug.getmetatable(io.stdout)
		filemeta.lock = lfs.lock
		filemeta.unlock = lfs.unlock
	end
end
--]]

local ffi = require 'ffi'
-- lfs already loaded at top if available

local PopenMeta -- Declare forward reference

if ffi.os == 'Windows' and lfs then
	local kernel32 = require 'ffi.req' 'Windows.sdk.kernel32'
	local C = ffi.C
	local CP_UTF8 = 65001

	-- Helper: UTF-8 string -> WCHAR*
	local function to_wide(str)
		if not str then return nil end
		local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
		if len == 0 then return nil end
		local buf = ffi.new("wchar_t[?]", len)
		kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
		return buf
	end

	-- _wpopen definition
	ffi.cdef[[
		typedef struct _iobuf FILE;
		FILE* _wpopen(const wchar_t* command, const wchar_t* mode);
		int _pclose(FILE* stream);
	]]

	-- Popen Object meta
	PopenMeta = {
		__index = {},
		__gc = function(self) self:close() end
	}

	function PopenMeta.__index:read(...)
		-- Reuse FileHandle.read logic from lfs_ffi
		if lfs.FileHandle and lfs.FileHandle.read then
			return lfs.FileHandle.read(self, ...)
		end
		-- fallback if read logic isn't exposed (should be via lfs_ffi modification)
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

	-- Override io.popen
	function io.popen(cmd, mode)
		mode = mode or 'r'
		local wcmd = to_wide(cmd)
		local wmode = to_wide(mode)
		local fp = C._wpopen(wcmd, wmode)

		if fp == nil then return nil, "popen failed" end

		return setmetatable({ fp = fp }, PopenMeta)
	end
end

-- [Modified] Reimplement io.open using FFI/lfs.fopen on Windows
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

	-- Current default handles (start with natives)
	local current_input = io.stdin
	local current_output = io.stdout

	-- Check if an object is our custom FFI FileHandle
	local function is_custom_handle(obj)
		local mt = getmetatable(obj)
		return (lfs.FileHandle and mt == lfs.FileHandle) or (PopenMeta and mt == PopenMeta)
	end

	function io.open(path, mode)
		-- Use lfs.fopen which uses _wfopen (Unicode aware) and returns a FFI-based FileHandle object
		return lfs.fopen(path, mode)
	end
	
	io.wopen = io.open -- Alias kept for compatibility

	-- Fix io.type to recognize custom handles
	function io.type(obj)
		if is_custom_handle(obj) then
			return obj.fp and "file" or "closed file"
		end
		return original_io_type(obj)
	end

	-- Implement io.tmpfile using os.tmpname + io.open
	-- Uses 'w+bD' mode on Windows (D = temporary/delete-on-close in MSVC)
	function io.tmpfile()
		local name = os.tmpname()
		if not name then return nil, "unable to generate tmp name" end
		-- Use FFI io.open which supports Unicode and wide modes
		return io.open(name, "w+bD")
	end

	-- Wrap global io functions to handle custom objects
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