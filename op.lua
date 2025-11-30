--[[
make lua functions for each operator.
it looks like i'm mapping 1-1 between metamethods and fields in this table.
useful for using Lua as a functional language.

TODO rename to 'ops'?
--]]

--local load = require 'string'.load	-- string.load = loadstring or load
local load = loadstring or load

-- test if we hae lua 5.3 bitwise operators
-- orrr I could just try each op and bail out on error
-- and honestly I should be defaulting to the 'bit' library anyways, esp in the case of luajit where it is translated to an asm opcode
local lua53 = _VERSION >= 'Lua 5.3'

-- [OPTIMIZATION] Detect LuaJIT for optimal bit library usage
local luajit = (jit ~= nil)

local symbolscode = [[

	-- which fields are unary operators
	local unary = {
		unm = true,
		bnot = true,
		len = true,
		lnot = true,
	}

	local symbols = {
		add = '+',
		sub = '-',
		mul = '*',
		div = '/',
		mod = '%',
		pow = '^',
		unm = '-',			-- unary
		concat = '..',
		eq = '==',
		ne = '~=',
		lt = '<',
		le = '<=',
		gt = '>',
		ge = '>=',
		land = 'and',		-- non-overloadable
		lor = 'or',			-- non-overloadable
		len = '#',			-- unary
		lnot = 'not',		-- non-overloadable, unary
]]
if lua53 then
	symbolscode = symbolscode .. [[
		idiv = '//',		-- 5.3
		band = '&',			-- 5.3
		bor = '|',			-- 5.3
		bxor = '~',			-- 5.3
		shl = '<<',			-- 5.3
		shr = '>>',			-- 5.3
		bnot = '~',			-- 5.3, unary
]]
end
symbolscode = symbolscode .. [[
	}
]]

local symbols, unary = assert(load(symbolscode..' return symbols, unary'))()

local code = symbolscode .. [[
	-- functions for operators
	local ops
	ops = {
]]

-- [OPTIMIZATION] For LuaJIT, inject the native bitop library directly into the ops table
if luajit then
	local bit = require("bit")
	-- LuaJIT bit op mapping to standard names used here
	-- Note: LuaJIT 'bit' library functions are: band, bor, bxor, bnot, lshift, rshift, arshift, rol, rror, tobit, tohex, bswap
	-- We map the common ones to the 'ops' table structure
	code = code .. [[
		band = require("bit").band,
		bor = require("bit").bor,
		bxor = require("bit").bxor,
		bnot = require("bit").bnot,
		shl = require("bit").lshift,
		shr = require("bit").rshift,
	]]
end

for name,symbol in pairs(symbols) do
	-- Skip bitwise ops if we already injected optimized JIT versions
	if not (luajit and (name == 'band' or name == 'bor' or name == 'bxor' or name == 'bnot' or name == 'shl' or name == 'shr')) then
		if unary[name] then
			code = code .. [[
			]]..name..[[ = function(a) return ]]..symbol..[[ a end,
	]]
		else
			code = code .. [[
			]]..name..[[ = function(a,b) return a ]]..symbol..[[ b end,
	]]
		end
	end
end
code = code .. [[
		index = function(t, k) return t[k] end,
		newindex = function(t, k, v)
			t[k] = v
			return t, k, v	-- ? should it return anything ?
		end,
		call = function(f, ...) return f(...) end,

		symbols = symbols,

		-- special pcall wrapping index, thanks luajit.  thanks.
		-- while i'm here, multiple indexing, so it bails out nil early, so it's a chained .? operator
		safeindex = function(t, ...)
			if select('#', ...) == 0 then return t end
			local res, v = pcall(ops.index, t, ...)
			if not res then return nil, v end
			return ops.safeindex(v, select(2, ...))
		end,
	}
	return ops
]]
return assert(load(code))()