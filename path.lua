--[[
path(pathtofile):open(mode) - to get a file handle
path(pathtofile):read() - to read a file in entirety
path(pathtofile):write() - to write to a file
path(pathtofile):dir() - to iterate through a directory listing
path(pathtofile):attr() - to get file attributes


TODO

- `path:cwd()` returns the *absolute* cwd, but `path` returns the directory `.` ...
... maybe path:cwd() should return `path'.'` and `path:abs()` should return the absolute path (using lfs.currentdir() for evaluation of '.')

- maybe `path` shoudl be the class, so I can use `path:isa` instead of `path.class:isa` ?

- right now path(a)(b)(c) is the same as path(a)/b/c
... maybe just use /'s and use call for something else? or don't use call at all?
--]]


-- [[ TODO - this block is also in ext/os.lua and ext/file.lua
local detect_os = require 'ext.detect_os'
local detect_lfs = require 'ext.detect_lfs'
local assert = require 'ext.assert'

local io = require 'ext.io'
local os = require 'ext.os'
local string = require 'ext.string'
local table = require 'ext.table'
local class = require 'ext.class'


-- Detect directory separator (from New Implementation logic)
local sep = package.config:sub(1,1)

-- Helper: Normalize path separators to '/' for internal consistency
local function normalize_sep(p)
	if sep == '\\' then
		return p:gsub('\\', '/')
	end
	return p
end

-- TODO this goes in file or os or somewhere in ext
local function simplifypath(s)
	local p = string.split(s, '/')
	for i=#p-1,1,-1 do
		-- convert a//b's to a/b
		if i > 1 then	-- don't remove empty '' as the first entry - this signifies a root path
			while p[i] == '' do p:remove(i) end
		end
		-- convert a/./b's to a/b
		while p[i] == '.' do p:remove(i) end
		-- convert a/b/../c's to a/c
		if p[i+1] == '..'
		and p[i] ~= '..'
		then
			if i == 1 and p[1] == '' then
				error("/.. absolute + previous doesn't make sense: "..tostring(s))	-- don't allow /../ to remove the base / ... btw this is invalid anyways ...
			end
			p:remove(i)
			p:remove(i)
		end
	end
	-- remove trailing '.''s except the first
	while #p > 1 and p[#p] == '.' do
		p:remove()
	end
	return p:concat'/'
end


-- PREPEND the path if fn is relative, otherwise use fn
-- I should reverse these arguments
-- but this function is really specific to the Path path state variable
local function appendPath(...)
	local fn, p = assert.types('appendPath', 2, 'string', 'string', ...)
	
	-- logic from New Implementation: handle absolute paths on right side
	if fn:sub(1,1) == '/' or (sep == '\\' and fn:match('^%a:')) then
		return fn
	end

	-- logic from New Implementation: basic join
	if p:sub(-1) ~= '/' then
		p = p .. '/'
	end
	return p .. normalize_sep(fn)
end


local Path = class()

--Path.sep = os.sep	-- TOO redundant?

function Path:init(args)
	-- Hybrid Init: Support both Old table-style and New string-style
	local path_str
	if type(args) == 'string' then
		path_str = args
	elseif Path:isa(args) then
		path_str = args.path
	else
		path_str = assert.type(
			assert.type(
				args,
				'table',
				'Path:init args'
			).path,
			'string',
			'Path:init args.path'
		)
	end
	
	-- always use / internally (New Implementation logic)
	self.path = normalize_sep(path_str or '.')

	assert.ne(self.path, nil)

	-- Remove trailing slash unless it's root (New Implementation logic)
	if #self.path > 1 and self.path:sub(-1) == '/' then
		self.path = self.path:sub(1, -2)
	end
end

-- wrappers
local mappings = {
	[io] = {
		lines = 'lines',
		open = 'wopen',
		read = 'readfile',
		write = 'writefile',
		append = 'appendfile',
		--getdir = 'getfiledir',	-- defined later, wrapped in Path
		--getext = 'getfileext',	-- defined later, wrapped in Path
	},
	[os] = {
		-- vanilla
		-- remove = 'remove', 	-- Replaced by explicit implementation below
		-- ext
		mkdir = 'mkdir',	-- using os.mkdir instead of lfs.mkdir becasuse of fallbacks ... and 'makeParents' flag
		rmdir = 'rmdir',
		copy = 'copy',      -- [FIX] Added copy mapping
		--move = 'move',	-- defined later for picking out path from arg
		-- exists = 'fileexists', -- Replaced by explicit implementation below
		-- isdir = 'isdir', -- Replaced by explicit implementation below
		--dir = 'listdir',		-- wrapping in path
		--rdir = 'rlistdir',

		-- TODO rename to 'fixpath'? 'fixsep'?
		fixpathsep = 'path',
	},
}

-- Detect LFS (Enhanced with lfs_ffi logic from New Implementation)
local has_lfs, lfs = pcall(require, 'lfs_ffi')
if not has_lfs then
	has_lfs, lfs = pcall(require, 'lfs')
end
-- Fallback to old detection if above fails (or just use what we got)
if not has_lfs then lfs = detect_lfs() end

if lfs then
	mappings[lfs] = {
		attr = 'attributes',
		symattr = 'symlinkattributes',
		cd = 'chdir',
		link = 'link',
		setmode = 'setmode',
		touch = 'touch',
		--cwd = 'currentdir',		-- TODO how about some kind of cwd or something ... default 'file' obj path is '.', so how about relating this to the default. path storage?
		--mkdir = 'mkdir',			-- in 'ext.os'
		--rmdir = 'rmdir',			-- in 'ext.os'
		--lock = 'lock',			-- in 'file' objects via ext.io.open
		--unlock = 'unlock',		-- in 'file' objects via ext.io.open
		lockdir = 'lock_dir',		-- can this be combined with lock() nah since lock() needs an open file handle.
	}
end

for obj,mapping in pairs(mappings) do
	for k,v in pairs(mapping) do
		Path[k] = function(self, ...)
			-- [FIX] Use tostring(self) to convert internal '/' to system separator (e.g. '\')
			-- This fixes issues where low-level APIs (like recursive mkdir) fail to parse paths with mixed separators on Windows.
			return obj[v](tostring(self), ...)
		end
	end
end

-- Path wrapping function, but return wraps in Path
function Path:getdir(...)
	local dir, name = io.getfiledir(self.path, ...)
	return Path{path=dir}, Path{path=name}
end

-- Path wrapping
function Path:getext(...)
	local base, ext = io.getfileext(self.path)
	return Path{path=base}, ext
end


-- [[ Attributes & Predicates (New Implementation Features)

local function get_mode(p)
	if not lfs then return nil end
	-- [FIX] Also use tostring(p) here for consistency
	return lfs.attributes(tostring(p), 'mode')
end

function Path:exists()
	if not lfs then return false end
	-- [FIX] Use tostring(self) for attributes check
	return lfs.attributes(tostring(self)) ~= nil
end

function Path:is_file()
	return get_mode(self) == 'file'
end
-- Alias
function Path:isfile() return self:is_file() end

function Path:is_dir()
	return get_mode(self) == 'directory'
end
-- Alias
function Path:isdir() return self:is_dir() end

function Path:is_link()
	if not lfs or not lfs.symlinkattributes then return false end
	-- [FIX] Use tostring(self)
	return lfs.symlinkattributes(tostring(self), 'mode') == 'link'
end

function Path:stat()
	if not lfs then return nil end
	-- [FIX] Use tostring(self)
	return lfs.attributes(tostring(self))
end

-- ]]


-- [[ Decomposition (New Implementation Features)

-- Returns a new Path object for the parent directory
function Path:parent()
	local p = self.path
	if p == '/' or p == '.' or p:match('^%a:/?$') then return nil end
	
	-- Find last separator
	local i = p:match('^.*()/')
	if not i then return Path('.') end
	
	local parent = p:sub(1, i-1)
	if parent == '' then return Path('/') end -- Root
	if parent:sub(-1) == ':' then return Path(parent .. '/') end -- Drive root "C:/"
	
	return Path(parent)
end

-- Returns string: filename
function Path:name()
	local i = self.path:match('^.*()/')
	if not i then return self.path end
	return self.path:sub(i+1)
end

-- Returns string: filename without last extension
function Path:stem()
	local name = self:name()
	local i = name:match('^.*()%.')
	if not i or i == 1 then return name end -- No dot or dotfile ".gitignore"
	return name:sub(1, i-1)
end

-- Returns string: extension (including dot), e.g. ".txt"
function Path:ext()
	local name = self:name()
	local i = name:match('^.*(%.%w+)$')
	return i or ''
end

-- ]]


-- [[ same as above but with non-lfs options.
-- TODO put them in io or os like I am doing to abstract non-lfs stuff elsewhere?

function Path:cwd()
	if lfs then
		return Path{path=lfs.currentdir()}
	else
		--[=[ TODO should I even bother with the non-lfs fallback?
		-- if so then use this:
		require 'ffi.req' 'c.stdlib'
		local dirp = unistd.getcwd(nil, 0)
		local dir = ffi.string(dirp)
		ffi.C.free(dirp)
		return dir
		--]=]
		if detect_os() then
			return Path{path=string.trim(io.readproc'cd')}
		else
			return Path{path=string.trim(io.readproc'pwd')}
		end
	end
end
--]]

-- convert relative to absolute paths
function Path:abs()
	-- Check for Unix root or Windows drive letter/network share
	if self.path:sub(1,1) == '/' or self.path:match('^%a:') then
		return self
	end
	-- Use lfs if available (New Logic preferred), fallback to Old Logic
	if lfs then
		return Path(lfs.currentdir()) / self
	end
	return Path:cwd()/self
end

-- os.listdir wrapper

function Path:move(to)
	if Path:isa(to) then to = to.path end
	-- [FIX] Use tostring(self)
	return os.move(tostring(self), to)
end

function Path:remove()
	-- Smart remove (handles files and empty dirs) - logic from New Implementation
	local p_sys = tostring(self)
	if self:is_dir() then
		return os.rmdir(p_sys)
	else
		return os.remove(p_sys)
	end
end

function Path:dir()
	local p_sys = tostring(self)
	if not os.isdir(p_sys) then
		error("can't dir() a non-directory: "..tostring(self.path))
	end
	return coroutine.wrap(function()
		for fn in os.listdir(p_sys) do
			coroutine.yield(Path{path=fn})
		end
	end)
end

function Path:rdir(callback)
	local p_sys = tostring(self)
	if not os.isdir(p_sys) then
		error("can't rdir() a non-directory: "..tostring(self.path))
	end
	return coroutine.wrap(function()
		for fn in os.rlistdir(p_sys, callback) do
			coroutine.yield(Path{path=fn})
		end
	end)
end


-- shorthand for splitting off ext and replacing it
-- Path:getext() splits off the last '.' and returns the letters after it
-- but for files with no ext it returns nil afterwards
-- so a file with only a single '.' at the end will produce a '' for an ext
-- and a file with no '.' will produce ext nil
-- so for compat, handle it likewise
-- for newext == nil, remove the last .ext from the filename
-- for newext == "", replace the last .ext with just a .
function Path:setext(newext)
	local base = self:stem() -- Use New 'stem' for better accuracy
	if newext then
		base = base .. '.' .. newext
	end
	return Path{path=base}
end

-- iirc setting __index and __newindex outside :init() is tough, since so much writing is still going on
--[[
TODO how to do the new interface?
specifically reading vs writing?

instead of __newindex for writing new files, how about path(path):write()
--]]
function Path:__call(k)
	assert.ne(self.path, nil)
	if k == nil then return self end
	if Path:isa(k) then k = k.path end
	
	-- Use appendPath logic (which now uses normalize_sep)
	local fn = assert.type(
		appendPath(k, self.path),
		'string',
		"Path:__call appendPath(k, self.path)")

	-- [FIX] Simplify the path to resolve '..'
	fn = simplifypath(fn)
	-- [FIX] If simplification results in empty string, use current directory
	if fn == '' then fn = '.' end

	return Path{
		path = assert.type(fn, 'string', "Path:__call simplifypath"),
	}
end

-- clever stl idea: path(a)/path(b) = path(a..'/'..b)
-- New Implementation: handle string concat logic in appendPath
Path.__div = Path.__call

-- return the path but for whatever OS we're using
function Path:__tostring()
	-- New Implementation Logic: Convert back to system separator for display/FFI usage
	if sep == '\\' then
		return self.path:gsub('/', '\\')
	end
	return self.path
end

-- Alias for C++ style explicit string conversion (New Implementation)
function Path:str()
	return tostring(self)
end

-- This is intended for shell / cmdline use
-- TODO it doesn't need to quote if there are no special characters present
-- also TODO make sure its escaping matches up with whatever OS is being used
function Path:escape()
	return('%q'):format(tostring(self))
end

function Path:__concat(b)
	return tostring(self) .. tostring(b)
end

-- don't coerce strings just yet
-- don't coerce abs path either
function Path.__eq(a,b) return Path(a).path == Path(b).path end
function Path.__lt(a,b) return a.path < b.path end
function Path.__le(a,b) return a.path <= b.path end

local pathSys = Path{path='.'}

return pathSys