local math = {}
for k,v in pairs(require 'math') do math[k] = v end

-- [Added] FFI support for Lua 5.3 integers
local ffi = require 'ffi'
local ok_int, _ = pcall(function() return ffi.new("int64_t") end)

if ok_int then
    math.maxinteger = ffi.new("int64_t", 9223372036854775807LL)
    math.mininteger = ffi.new("int64_t", -9223372036854775808LL)
    
    function math.tointeger(x)
        x = tonumber(x)
        if not x then return nil end
        -- Check if fractional
        if x % 1 ~= 0 then return nil end
        -- Check range (double can represent exact integers up to 2^53)
        -- But Lua 5.3 allows wrapping? No, tointeger returns nil if not representable.
        -- Actually tointeger casts to integer if representable.
        if x > tonumber(math.maxinteger) or x < tonumber(math.mininteger) then
            return nil
        end
        return ffi.new("int64_t", x)
    end
    
    function math.type(x)
        if type(x) == 'number' then
            -- Plain Lua number is usually double in LuaJIT (unless mapped to int64 by FFI logic, but type() returns 'cdata' for int64)
            -- Wait, type(1LL) is 'cdata' in LuaJIT.
            return 'float' 
        elseif type(x) == 'cdata' then
            if ffi.istype("int64_t", x) or ffi.istype("uint64_t", x) then
                return 'integer'
            end
        end
        return nil
    end
    
    function math.ult(m, n)
        return ffi.cast("uint64_t", m) < ffi.cast("uint64_t", n)
    end
else
    -- Fallback for systems without 64-bit int support (unlikely with LuaJIT)
    math.maxinteger = 2^53 - 1
    math.mininteger = -(2^53 - 1)
    
    function math.tointeger(x)
        x = tonumber(x)
        if not x or x % 1 ~= 0 then return nil end
        return x
    end
    
    function math.type(x)
        return type(x) == 'number' and 'float' or nil
    end
    
    function math.ult(m, n)
        return m < n -- Approximate
    end
end

math.nan = 0/0

math.e = math.exp(1)

-- luajit and lua 5.1 compat ...
if not math.atan2 then math.atan2 = math.atan end
-- also note, code that uses math.atan(y,x) in luajit will instead just call math.atan(y) ...

function math.cbrt(x)
	return math.sign(x) * math.abs(x)^(1/3)
end

function math.clamp(v,min,max)
	return math.max(math.min(v, max), min)
end

function math.sign(x)
	if x < 0 then return -1 end
	if x > 0 then return 1 end
	return 0
end

function math.trunc(x)
	if x < 0 then return math.ceil(x) else return math.floor(x) end
end

function math.round(x)
	return math.floor(x+.5)
end

function math.isnan(x) return x ~= x end
function math.isinf(x) return x == math.huge or x == -math.huge end
function math.isfinite(x) return tonumber(x) and not math.isnan(x) and not math.isinf(x) end

function math.isprime(n)
	if n < 2 then return false end	-- 1 isnt prime
	for i=2,math.floor(math.sqrt(n)) do
		if n%i == 0 then
			return false
		end
	end
	return true
end

-- assumes n is a non-negative integer.  this isn't the Gamma function
function math.factorial(n)
	local prod = 1
	for i=1,n do
		prod = prod * i
	end
	return prod
end

function math.factors(n)
	local table = require 'ext.table'
	local f = table()
	for i=1,n do
		if n%i == 0 then
			f:insert(i)
		end
	end
	return f
end

-- returns a table containing the prime factorization of the number
function math.primeFactorization(n)
	local table = require 'ext.table'
	n = math.floor(n)
	local f = table()
	while n > 1 do
		local found = false
		for i=2,math.floor(math.sqrt(n)) do
			if n%i == 0 then
				n = math.floor(n/i)
				f:insert(i)
				found = true
				break
			end
		end
		if not found then
			f:insert(n)
			break
		end
	end
	return f
end

function math.gcd(a,b)
	return b == 0 and a or math.gcd(b, a % b)
end

-- if this math lib gets too big ...
function math.mix(a,b,s)
	return a * (1 - s) + b * s
end

return math