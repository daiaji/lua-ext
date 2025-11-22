local ffi = require 'ffi'
require 'ffi.req' 'c.stdlib'

--[[
uses C malloc paired with ffi-based garbage collection
typecasts correctly
and retains the ability to manually free
(so you don't have to manually free it)
NOTICE casting *AFTER* wrapping will crash, probably due to the gc thinking the old pointer is gone
also ffi.gc retains type, so no worries about casting before
...
that was true, but now it's always losing the ptr and crashing, so I'm going to fall back on ffi.new
--]]
local function gcnew(T, n)
	--[[
	local ptr = ffi.C.malloc(n * ffi.sizeof(T))
	ptr = ffi.cast(T..'*', ptr)
	ptr = ffi.gc(ptr, ffi.C.free)
	--]]
	-- [Modified] Use ffi.new as recommended by LuaJIT (safer and cleaner)
	local ptr = ffi.new(T..'['..n..']')
	
	return ptr
end

--[[
manual free of a pointer
frees the ptr and removes it from the gc
(just in case you want to manually free a pointer)
--]]
local function gcfree(ptr)
	-- [Modified] ffi.new allocated objects are managed by GC automatically.
	-- Calling free on ffi.new pointers is invalid/unnecessary.
	-- However, to force release of gc-anchored resources:
	ffi.gc(ptr, nil) 
	if ffi.istype(ptr, ffi.cast("void*", 0)) then
		-- Only call free if it was malloc'd (heuristic check or strictly for legacy compat)
		-- For ffi.new, we just let GC handle it after untethering if there was a custom finalizer.
		-- Since gcnew now uses ffi.new, manual free is fundamentally incompatible.
		-- We leave this as a no-op for ffi.new objects or explicit free for malloc'd ones if mixed.
		-- ffi.C.free(ptr) 
	end
end

return {
	new = gcnew,
	free = gcfree,
}