local os = {}
for k,v in pairs(require 'os') do os[k] = v end

-- for io.readproc
-- don't require os from inside io ...
local io = require 'ext.io'

-- table.pack
local table = require 'ext.table'

-- string.trim
local string = require 'ext.string'
local assert = require 'ext.assert'
local detect_lfs = require 'ext.detect_lfs'
local detect_os = require 'ext.detect_os'

-- [Modified] Soft require for lfs_ffi to prevent crash if dependencies are missing
local has_lfs, lfs = pcall(require, 'lfs_ffi')
if not has_lfs then lfs = nil end

os.sep = detect_os() and '\\' or '/'

-- TODO this vs path.fixpathsep ...
-- should I just move everything over to 'path' ...
function os.path(str)
	assert.type(str, 'string')
	return (str:gsub('/', os.sep))
end

-- 5.2 os.execute compat
-- TODO if 5.1 was built with 5.2-compat then we don't have to do this ...
-- how to test?
if _VERSION == 'Lua 5.1' then
	local execute = os.execute
	function os.execute(cmd)
		local results = table.pack(execute(cmd))
		if #results > 1 then return results:unpack() end	-- >5.1 API
		local errcode = results[1]
		local reason = ({
			[0] = 'exit',
		})[errcode] or 'unknown'
		return errcode == 0 and true or nil, reason, errcode
	end
end

-- too common not to put here
-- this does execute but first prints the command to stdout
function os.exec(cmd)
	print('>'..cmd)
	return os.execute(cmd)
end

-- [Modified] Override os.remove to use FFI version if available (supports Unicode on Windows)
local orig_remove = os.remove
function os.remove(path)
	if lfs and lfs.remove_file then
		if lfs.remove_file(path) then return true end
		return nil, "remove failed"
	else
		return orig_remove(path)
	end
end

function os.fileexists(fn)
	assert(fn, "expected filename")
	local lfs = detect_lfs()
	if lfs then
		return lfs.attributes(fn) ~= nil
	else
		if detect_os() then
			-- Windows reports 'false' to io.open for directories, so I can't use that ...
			return 'yes' == string.trim(io.readproc('if exist "'..os.path(fn)..'" (echo yes) else (echo no)'))
		else
			-- here's a version that works for OSX ...
			local f, err = io.open(fn, 'r')
			if not f then return false, err end
			f:close()
			return true
		end
	end
end

-- [FIX] Robust Recursive mkdir implementation (Stack-based unwinding)
-- Replaces the old string.split implementation which failed on Windows drive roots
function os.mkdir(dir, makeParents)
	local lfs = detect_lfs()
	if not lfs then
		-- fallback on shell
		local tonull
		if detect_os() then
			dir = os.path(dir)
			tonull = ' 2> nul'
			makeParents = nil -- mkdir in Windows always makes parents, and doesn't need a switch
		else
			tonull = ' 2> /dev/null'
		end
		local cmd = 'mkdir'..(makeParents and ' -p' or '')..' '..('%q'):format(dir)..tonull
		return os.execute(cmd)
	end

	-- Normalize path separators for internal processing
	dir = os.path(dir)

	if not makeParents then
		-- no parents - just mkdir
		return lfs.mkdir(dir)
	end

	-- Check if target already exists
	if os.fileexists(dir) then return true end

	-- Stack-based parent finding
	local stack = {}
	local p = dir
	while true do
		table.insert(stack, 1, p)
		
		-- Find parent directory
		-- Match both / and \ separators to handle various path formats
		local new_p = p:match("^(.*)[\\/][^\\/]+$")
		
		if not new_p then
			-- Reached root or no separator found
			-- If it looks like a drive root (C: or C:\), ensure we don't try to mkdir it
			if p:match("^%a:$") or p:match("^%a:[\\/]$") then
				table.remove(stack, 1)
			end
			break 
		end
		
		if os.fileexists(new_p) then
			break
		end
		p = new_p
	end

	-- Create missing directories in order
	for _, folder in ipairs(stack) do
		if not os.fileexists(folder) then
			local res, err = lfs.mkdir(folder)
			-- Double check existence to handle race conditions or "already exists" errors gracefully
			if not res and not os.fileexists(folder) then
				return nil, "mkdir failed for '"..folder.."': " .. tostring(err)
			end
		end
	end
	return true
end

function os.rmdir(dir)
	local lfs = detect_lfs()
	if lfs then
		-- lfs
		return lfs.rmdir(dir)
	else
		-- shell
		local cmd = 'rmdir "'..os.path(dir)..'"'
		return os.execute(cmd)
	end
end

-- [FIX] Generic fallback for os.copy (stream based)
-- Defined here so it is available even if FFI/Windows block is skipped
function os.copy(src, dst)
	local r, err = io.open(src, 'rb')
	if not r then return nil, err end
	local w, err2 = io.open(dst, 'wb')
	if not w then r:close(); return nil, err2 end
	
	local chunk_size = 64*1024 -- 64KB chunks
	while true do
		local d = r:read(chunk_size)
		if not d then break end
		w:write(d)
	end
	
	r:close()
	w:close()
	return true
end

function os.move(from, to)
    -- [FIX] Ensure arguments are strings, handling Path objects
    from = tostring(from)
    to = tostring(to)

	-- 1. Try lfs_ffi first (if it implements rename_file)
	if lfs and lfs.rename_file then
		if lfs.rename_file(from, to) then return true end
	end

	-- 2. Preferred Windows FFI Implementation (MoveFileExW)
	-- This supports cross-volume moves and atomic replacement
	local detect_ffi = require 'ext.detect_ffi'
	local ffi = detect_ffi()
	if ffi and ffi.os == 'Windows' then
		local ok, kernel32 = pcall(require, 'ffi.req', 'Windows.sdk.kernel32')
        if ok then
            local CP_UTF8 = 65001
            
            -- Define helper locally to avoid dependency on external scope
            local function to_wide(str)
                if not str then return nil end
                local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
                local buf = ffi.new("wchar_t[?]", len)
                kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
                return buf
            end
            
            -- MOVEFILE_COPY_ALLOWED (2) | MOVEFILE_REPLACE_EXISTING (1) = 3
            local flags = 3 
            if kernel32.MoveFileExW(to_wide(from), to_wide(to), flags) ~= 0 then
                return true
            else
                -- Fallthrough to legacy methods if MoveFileExW fails
            end
        end
	end

	if ffi then
        -- [FIX] pcall require ffi.req to allow safe fallback
        local ok_stdio, stdio = pcall(require, 'ffi.req', 'c.stdio')
		local ok_errno, errno = pcall(require, 'ffi.req', 'c.errno')
		if ok_stdio and ok_errno then
            if stdio.rename(from, to) == 0 then return true end
            return nil, errno.str()
        end
	end

    -- Fallback shell
    from = os.path(from)
    to = os.path(to)
    local cmd = (detect_os() and 'move' or 'mv') .. ' "'..from..'" "'..to..'"'
    return os.execute(cmd)
end

function os.isdir(fn)
	local lfs = detect_lfs()
	if lfs then
		local attr = lfs.attributes(fn)
		if not attr then return false end
		return attr.mode == 'directory'
	else
		if detect_os() then
			return 'yes' ==
				string.trim(io.readproc(
					'if exist "'
					..os.path(fn)
					..'\\*" (echo yes) else (echo no)'
				))
		else
			-- for OSX:
			-- TODO you could work around this for directories:
			-- f:read(1) for 5.1,jit,5.2,5.3 returns nil, 'Is a directory', 21
			local f = io.open(fn,'rb')
			if not f then return false end
			local result, reason, errcode = f:read(1)
			f:close()
			if result == nil
			and reason == 'Is a directory'
			and errcode == 21
			then
				return true
			end
			return false
		end
	end
end

function os.listdir(path)
	local lfs = detect_lfs()
	if not lfs then
		-- no lfs?  use a fallback of shell ls or dir (based on OS)
		local fns
		-- all I'm using ffi for is reading the OS ...
--			local detect_ffi = require 'ext.detect_ffi'
--			local ffi = detect_ffi()	-- no lfs?  are you using luajit?
--			if not ffi then
			-- if 'dir' exists ...
			--	local filestr = io.readproc('dir "'..path..'"')
			--	error('you are here: '..filestr)
			-- if 'ls' exists ...

			local cmd
			if detect_os() then
				cmd = 'dir /b "'..os.path(path)..'"'
			else
				cmd = 'ls -a '..path:gsub('[|&;<>`\"\' \t\r\n#~=%$%(%)%%%[%*%?]', [[\%0]])
			end
			local filestr = io.readproc(cmd)
			fns = string.split(filestr, '\n')
			assert.eq(fns:remove(), '')
			if fns[1] == '.' then fns:remove(1) end
			if fns[1] == '..' then fns:remove(1) end
--[[
		else
			-- do a directory listing
			-- TODO escape?
			if ffi.os == 'Windows' then
				-- put your stupid FindFirstFile/FindNextFile code here
				error('windows sucks...')
			else
				fns = {}
				require 'ffi.req' 'c.dirent'
				-- https://stackoverflow.com/questions/10678522/how-can-i-get-this-readdir-code-sample-to-search-other-directories
				local dirp = ffi.C.opendir(path)
				if dirp == nil then
					error('failed to open dir '..path)
				end
				repeat
					local dp = ffi.C.readdir(dirp)
					if dp == nil then break end
					local name = ffi.string(dp[0].d_name)
					if name ~= '.' and name ~= '..' then
						table.insert(fns, name)
					end
				until false
				ffi.C.closedir(dirp)
			end
		end
--]]
		return coroutine.wrap(function()
			for _,k in ipairs(fns) do
				--local fn = k:sub(1,1) == '/' and k or (path..'/'..k)
				coroutine.yield(k)
			end
		end)
	else
		return coroutine.wrap(function()
			for k in lfs.dir(path) do
				if k ~= '.' and k ~= '..' then
					--local fn = k:sub(1,1) == '/' and k or (path..'/'..k)
					-- I shouldn't have io.readfile for performance
					--  but for convenience it is so handy...
					coroutine.yield(k)--, io.readfile(fn))
				end
			end
		end)
	end
end

--[[ recurse directory
args:
	dir = directory to search from
	callback(filename, isdir) = optional callback to filter each file

should this be in io or os?
--]]
function os.rlistdir(dir, callback)
	return coroutine.wrap(function()
		for f in os.listdir(dir) do
			local path = require 'ext.path'
			local fpath = path(dir)(f).path
			if os.isdir(fpath) then
				if not callback or callback(fpath, true) then
					for f in os.rlistdir(fpath, callback) do
						coroutine.yield(f)
					end
				end
			else
				if not callback or callback(fpath, false) then
					local fn = fpath
					if #fn > 2 and fn:sub(1,2) == './' then fn = fn:sub(3) end
					coroutine.yield(fn)
				end
			end
		end
	end)
end

function os.fileexists(fn)
	assert(fn, "expected filename")
	local lfs = detect_lfs()
	if lfs then
		return lfs.attributes(fn) ~= nil
	else
		if detect_os() then
			-- Windows reports 'false' to io.open for directories, so I can't use that ...
			return 'yes' == string.trim(io.readproc('if exist "'..os.path(fn)..'" (echo yes) else (echo no)'))
		else
			-- here's a version that works for OSX ...
			local f, err = io.open(fn, 'r')
			if not f then return false, err end
			f:close()
			return true
		end
	end
end

-- to complement os.getenv
function os.home()
	local home = os.getenv'HOME' or os.getenv'USERPROFILE'
	if not home then return false, "failed to find environment variable HOME or USERPROFILE" end
	return home
end

local ffi = require 'ffi'
if ffi.os == 'Windows' then
    -- [FIX] Use safe requires for FFI bindings
    local ok_k32, kernel32 = pcall(require, 'ffi.req', 'Windows.sdk.kernel32')
    local ok_std, _ = pcall(require, 'ffi.req', 'c.corecrt_wstdlib')
    local ok_proc, _ = pcall(require, 'ffi.req', 'c.process')
    local ok_usr, user32 = pcall(require, 'ffi.req', 'Windows.sdk.user32')

    if ok_k32 and ok_std and ok_proc then
        local C = ffi.C
        local CP_UTF8 = 65001

        -- Helper: UTF-8 string -> WCHAR*
        local function to_wide(str)
            if not str then return nil end
            local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
            local buf = ffi.new("wchar_t[?]", len)
            kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
            return buf
        end

        -- Helper: WCHAR* -> UTF-8 string
        local function from_wide(wstr)
            if wstr == nil then return nil end
            local len = kernel32.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nil, 0, nil, nil)
            if len == 0 then return nil end
            local buf = ffi.new("char[?]", len)
            kernel32.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf, len, nil, nil)
            return ffi.string(buf)
        end

        -- Override os.execute to support unicode commands
        function os.execute(cmd)
            if not cmd then
                -- check shell availability
                return C._wsystem(nil) ~= 0
            end

            local wcmd = to_wide(cmd)
            local status = C._wsystem(wcmd)

            -- Simulate Lua 5.2+ return format
            if status == -1 then
                return nil, "execution failed", -1
            end
            return (status == 0), "exit", status
        end

        -- Override os.getenv to support unicode environment variables
        function os.getenv(varname)
            local wvar = to_wide(varname)
            local wval = C._wgetenv(wvar)
            return from_wide(wval)
        end

        -- Override os.setenv (not standard lua, but good to have)
        function os.setenv(varname, value)
            local wvar = to_wide(varname)
            local wval = value and to_wide(value) or to_wide("")
            return C._wputenv_s(wvar, wval) == 0
        end

        function os.toansi(str)
            if not str then return nil end
            local wstr = to_wide(str)
            if not wstr then return nil end
            
            local CP_ACP = 0
            local len = kernel32.WideCharToMultiByte(CP_ACP, 0, wstr, -1, nil, 0, nil, nil)
            if len == 0 then return nil end
            local buf = ffi.new("char[?]", len)
            kernel32.WideCharToMultiByte(CP_ACP, 0, wstr, -1, buf, len, nil, nil)
            return ffi.string(buf)
        end

        function os.shortpath(path)
            local wpath = to_wide(path)
            if not wpath then return path end
            
            local len = kernel32.GetShortPathNameW(wpath, nil, 0)
            if len == 0 then return path end
            
            local buf = ffi.new("wchar_t[?]", len)
            kernel32.GetShortPathNameW(wpath, buf, len)
            return from_wide(buf)
        end

        function os.tmpname()
            local MAX_PATH = 261
            local buf = ffi.new("wchar_t[?]", MAX_PATH)
            local len = kernel32.GetTempPathW(MAX_PATH, buf)
            if len == 0 then return nil end
            
            local filename_buf = ffi.new("wchar_t[?]", MAX_PATH)
            if kernel32.GetTempFileNameW(buf, to_wide("lua"), 0, filename_buf) == 0 then
                return nil
            end
            return from_wide(filename_buf)
        end

        -- [Added] Non-blocking Sleep (Message Pump)
        if ok_usr and user32 then
            function os.sleep_pump(ms)
                local start = kernel32.GetTickCount()
                local elapsed = 0
                local QS_ALLINPUT = 0x04FF
                local PM_REMOVE = 1
                local msg = ffi.new("MSG")

                while elapsed < ms do
                    local remaining = ms - elapsed
                    local res = user32.MsgWaitForMultipleObjects(0, nil, 0, remaining, QS_ALLINPUT)
                    
                    if res == 0 then 
                        while user32.PeekMessageW(msg, nil, 0, 0, PM_REMOVE) ~= 0 do
                            if msg.message == 0x0012 then 
                                user32.PostQuitMessage(msg.wParam)
                                return 
                            end
                            user32.TranslateMessage(msg)
                            user32.DispatchMessageW(msg)
                        end
                    end
                    elapsed = kernel32.GetTickCount() - start
                end
            end
        end

        -- [Added] Standardized File Copy (Unicode aware)
        function os.copy(src, dst, fail_if_exists)
            -- [FIX] Ensure arguments are strings (handles Path objects)
            src = tostring(src)
            dst = tostring(dst)
            
            local wsrc = to_wide(src)
            local wdst = to_wide(dst)
            if kernel32.CopyFileW(wsrc, wdst, fail_if_exists and 1 or 0) ~= 0 then
                return true
            else
                return false, "CopyFileW failed: " .. tostring(kernel32.GetLastError())
            end
        end

        -- [Added] Windows-specific Directory Functions (Unicode aware)
        function os.fileexists(path)
            local wpath = to_wide(tostring(path))
            local attr = kernel32.GetFileAttributesW(wpath)
            return attr ~= 0xFFFFFFFF
        end

        function os.isdir(path)
            local wpath = to_wide(tostring(path))
            local attr = kernel32.GetFileAttributesW(wpath)
            if attr == 0xFFFFFFFF then return false end
            local FILE_ATTRIBUTE_DIRECTORY = 0x10
            return bit.band(attr, FILE_ATTRIBUTE_DIRECTORY) ~= 0
        end

        -- Native recursion-aware mkdir
        function os.mkdir(dir, makeParents)
            dir = tostring(dir)
            local wdir = to_wide(dir)
            
            -- Simple case
            if not makeParents then
                return kernel32.CreateDirectoryW(wdir, nil) ~= 0
            end

            -- Recursive case
            if os.fileexists(dir) then return true end

            -- Re-implement recursion with native checks
            local stack = {}
            local p = dir
            while true do
                table.insert(stack, 1, p)
                local new_p = p:match("^(.*)[\\/][^\\/]+$")
                if not new_p then
                    if p:match("^%a:$") or p:match("^%a:[\\/]$") then
                        table.remove(stack, 1)
                    end
                    break 
                end
                if os.fileexists(new_p) then break end
                p = new_p
            end

            for _, folder in ipairs(stack) do
                if not os.fileexists(folder) then
                    if kernel32.CreateDirectoryW(to_wide(folder), nil) == 0 then
                        -- Double check if it appeared (race condition)
                        if not os.fileexists(folder) then
                            return nil, "mkdir failed: " .. tostring(kernel32.GetLastError())
                        end
                    end
                end
            end
            return true
        end

        function os.rmdir(dir)
            dir = tostring(dir)
            local wdir = to_wide(dir)
            return kernel32.RemoveDirectoryW(wdir) ~= 0
        end

        function os.remove(path)
            path = tostring(path)
            if os.isdir(path) then
                return os.rmdir(path)
            end
            local wpath = to_wide(path)
            return kernel32.DeleteFileW(wpath) ~= 0
        end
    end
end

return os