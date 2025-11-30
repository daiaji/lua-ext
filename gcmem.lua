local ffi = require 'ffi'
-- [FIX] Removed dependency on 'c.stdlib' as we now use ffi.new
-- require 'ffi.req' 'c.stdlib'

--[[
uses C malloc paired with ffi.gc (Old behavior)
Now uses ffi.new (New behavior) which handles GC automatically.
Retains API compatibility.
--]]
local function gcnew(T, n)
	--[[
	local ptr = ffi.C.malloc(n * ffi.sizeof(T))
	ptr = ffi.cast(T..'*', ptr)
	ptr = ffi.gc(ptr, ffi.C.free)
	--]]
	-- [Modified] Use ffi.new as recommended by LuaJIT (safer and cleaner)
	-- This returns a GC-managed cdata object.
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
	-- Calling free on ffi.new pointers is invalid.
	-- However, we can untether the GC callback if one existed (though ffi.new usually doesn't have one set via ffi.gc unless manual)
	-- For ffi.new VLA, we just clear the reference in the caller.
	
	-- To force release of resources if this WAS a manually managed pointer (legacy support):
	ffi.gc(ptr, nil) 
	
	-- Note: We cannot safely call ffi.C.free(ptr) here because we don't know 
	-- if 'ptr' came from ffi.new (GC managed) or ffi.C.malloc.
	-- Since gcnew now produces ffi.new pointers, calling free is dangerous.
	-- We assume this function is a no-op for ffi.new objects.
end

return {
	new = gcnew,
	free = gcfree,
}