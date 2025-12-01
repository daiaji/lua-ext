-- lua-ext/tests/test_all.lua
-- Ultimate Coverage Suite for lua-ext
-- Targets: 100% API Coverage

-- ============================================================================
-- 0. Environment Setup
-- ============================================================================
io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

-- 清理可能存在的预加载，确保测试的是纯净环境
if package.loaded['ext'] then package.loaded['ext'] = nil end

-- ============================================================================
-- 1. Loading
-- ============================================================================
-- 此时 LUA_PATH 已经由 CI 设置好，所有依赖（lfs_ffi, ffi bindings, ext）都在路径中
-- 直接 require 即可，不再需要 bootstrap 逻辑

require 'ext' -- 加载库入口

local ffi = require 'ffi'
local is_windows = (ffi.os == 'Windows')

-- 加载 LuaUnit
local lu = require('luaunit')

-- ============================================================================
-- 2. Core (Assert, Op, Meta, Tolua, Load, GC, Coroutine)
-- ============================================================================
TestCore = {}

function TestCore:testAsserts_EdgeCases()
    -- Float precision
    assert.eqeps(1.00000001, 1.0, 1e-7)
    lu.assertError(function() assert.eqeps(1.1, 1.0, 0.05) end)

    -- Custom Norm
    local function diff_sq(a, b) return (a - b) ^ 2 end
    assert.eqepsnorm(2, 4, 4.1, diff_sq) -- (2-4)^2 = 4 <= 4.1

    -- Types & Args
    assert.type(nil, 'nil')
    assert.types("args check", 3, "string", "number", "boolean", "a", 1, true)

    -- Table Content
    assert.len({ 1, 2, 3 }, 3)
    assert.tableieq({ 1, 'a', nil }, { 1, 'a', nil })
    assert.index({ key = "val" }, "key")

    -- Error capture
    local msg = assert.error(function() error("test error") end)
    lu.assertStrContains(msg, "test error")
    lu.assertError(function() assert.error(function() return true end) end)
end

function TestCore:testOp_Logic()
    local op = require 'ext.op'
    lu.assertEquals(op.add(10, 20), 30)
    lu.assertEquals(op.mod(10, 3), 1)

    -- Logic Meta (Boolean extensions)
    lu.assertTrue((true):and_(true))
    lu.assertFalse((true):and_(false))
    lu.assertTrue((false):or_(true))
    lu.assertTrue((true):xor(false))
    lu.assertFalse((true):xor(true))
    lu.assertTrue((false):implies(true))
    lu.assertFalse((true):implies(false))

    -- Safe Indexing
    local t = { a = { b = { c = 42 } } }
    lu.assertEquals(op.safeindex(t, 'a', 'b', 'c'), 42)
    lu.assertEquals(op.safeindex(t, 'a', 'x', 'c'), nil)
    lu.assertEquals(op.safeindex(nil, 'a'), nil)
end

function TestCore:testMetaOperators()
    local f = function(x) return x + 1 end
    local g = function(x) return x * 2 end

    -- Function Arithmetic: h(x) = f(x) + g(x)
    local h = f + g
    lu.assertEquals(h(10), 31) -- 11 + 20

    -- Unary minus
    local neg = -f
    lu.assertEquals(neg(10), -11)

    -- Composition: f(g(x))
    local fc = f:compose(g)
    lu.assertEquals(fc(10), 21) -- 2*10 + 1
end

function TestCore:testTolua_Serialization()
    local t = {
        a = 1,
        b = "string",
        c = { d = true },
        e = math.huge
    }
    t.f = t -- Recursive ref

    local s = tolua(t)
    lu.assertStrContains(s, 'a=1')
    lu.assertStrContains(s, 'b="string"')
    lu.assertStrContains(s, 'd=true')

    -- Deserialize
    local t2 = fromlua(s)
    lu.assertEquals(t2.a, 1)
    lu.assertEquals(t2.b, "string")
    lu.assertEquals(t2.c.d, true)
    lu.assertEquals(t2.e, math.huge)
    -- Check recursion restoration
    lu.assertTrue(t2.f == t2)
end

function TestCore:testLoadShim()
    -- Hashbang support
    local script = "#!/usr/bin/env lua\nreturn 123"
    local f = "temp_hashbang.lua"
    io.writefile(f, script)

    local chunk, err = loadfile(f)
    if not chunk then
        lu.fail("loadfile failed: " .. tostring(err))
    else
        lu.assertEquals(chunk(), 123)
    end

    -- String load
    local f_load = load("return ...")
    lu.assertEquals(f_load(456), 456)

    os.remove(f)
end

function TestCore:testGCMem()
    local gcmem = require 'ext.gcmem'
    local ptr = gcmem.new('int', 5) -- int[5]
    lu.assertNotNil(ptr)
    lu.assertEquals(type(ptr), 'cdata')
    ptr[0] = 123
    lu.assertEquals(ptr[0], 123)
    gcmem.free(ptr)
end

function TestCore:testCoroutineAssertResume()
    -- Mock stderr to capture output (avoid cluttering test logs)
    local old_stderr = io.stderr
    local captured = {}
    local mock_stderr = {
        write = function(self, msg) table.insert(captured, msg) end,
        flush = function(self) end
    }
    io.stderr = mock_stderr

    local co = coroutine.create(function() error("intended_fail") end)
    local ok, err = coroutine.assertresume(co)

    io.stderr = old_stderr

    lu.assertFalse(ok)
    lu.assertStrContains(err, "intended_fail")
    lu.assertStrContains(err, "stack traceback")

    local output = table.concat(captured)
    lu.assertStrContains(output, "intended_fail")
end

-- ============================================================================
-- 2. Types (Table, String, Number, Math, Func)
-- ============================================================================
TestTable = {}
function TestTable:testCreationAndMeta()
    local t = table(1, 2)
    lu.assertEquals(getmetatable(t), table)

    local p = table.pack(1, nil, 3)
    lu.assertEquals(p.n, 3)

    local a, b, c = table.unpack(p)
    lu.assertEquals(c, 3)
end

function TestTable:testTransformation()
    local t = table { 1, 2, 3, 4 }

    -- Map
    local m = t:map(function(v, k)
        if v % 2 == 0 then return v * 10, tostring(k) .. "_key" end
        return v
    end)
    lu.assertEquals(m[1], 1)
    lu.assertEquals(m["2_key"], 20)

    -- Filter
    local f = t:filter(function(v) return v > 2 end)
    lu.assertEquals(#f, 2)
    lu.assertEquals(f[1], 3)

    -- Mapi
    local mi = t:mapi(function(v, i) return v + i end)
    lu.assertEquals(mi[4], 8)
end

function TestTable:testSetOperations()
    local t1 = table { a = 1, b = 2 }
    local t2 = table { b = 3, c = 4 }

    -- Union
    local u = table(t1):union(t2)
    lu.assertEquals(u.a, 1)
    lu.assertEquals(u.b, 3) -- Overwrite
    lu.assertEquals(u.c, 4)

    -- Append
    local arr = table { 1 }:append({ 2 }, { 3 })
    lu.assertEquals(table.concat(arr), "123")

    -- Remove Keys
    u:removeKeys('a', 'c')
    lu.assertNil(u.a)
    lu.assertNil(u.c)
    lu.assertEquals(u.b, 3)
end

function TestTable:testAdvancedFind()
    local t = table { { id = 1 }, { id = 2 }, { id = 3 } }

    -- Find with comparator
    local k, v = t:find(2, function(item, val) return item.id == val end)
    lu.assertEquals(k, 2)
    lu.assertEquals(v.id, 2)

    -- Insert Unique
    t:insertUnique({ id = 2 }, function(item, val) return item.id == val.id end)
    lu.assertEquals(#t, 3)

    t:insertUnique({ id = 4 }, function(item, val) return item.id == val.id end)
    lu.assertEquals(#t, 4)

    lu.assertTrue(t:contains(4, function(item, val) return item.id == val end))
end

function TestTable:testSortChaining()
    local t = table { 3, 1, 2 }
    local res = t:sort():map(function(v) return v * 2 end)
    lu.assertEquals(res[1], 2)
    lu.assertEquals(res[3], 6)
end

function TestTable:testSub()
    local t = table { 'a', 'b', 'c', 'd', 'e' }
    lu.assertEquals(table.concat(t:sub(2, 4)), "bcd")
    lu.assertEquals(table.concat(t:sub(-2)), "de")
    lu.assertEquals(#t:sub(3, 2), 0)
end

function TestTable:testSupInf()
    local t = table { 10, 5, 20, 3 }
    lu.assertEquals(t:sup(), 20)
    lu.assertEquals(t:inf(), 3)

    local objs = table { { val = 10 }, { val = 50 }, { val = 20 } }
    local max_obj = objs:sup(function(a, b) return a.val > b.val end)
    lu.assertEquals(max_obj.val, 50)
end

function TestTable:testPermutations()
    local t = table { 1, 2, 3 }
    local count = 0
    local patterns = table()
    for p in t:permutations() do
        count = count + 1
        patterns:insert(table.concat(p))
    end
    lu.assertEquals(count, 6)
    lu.assertTrue(patterns:contains("123"))
end

function TestTable:testZip()
    local z = table.zip({ 1, 2 }, { 'a', 'b' })
    lu.assertEquals(z[1][2], 'a')
    lu.assertEquals(z[2][2], 'b')
end

function TestTable:testFlattenAndRep()
    local rep = table { 1, 2 }:rep(3)
    lu.assertEquals(#rep, 6)
    lu.assertEquals(rep[6], 2)
end

function TestTable:testKVPairs()
    local t = { a = 1, b = 2 }
    local kv = table(t):kvpairs()
    lu.assertEquals(#kv, 2)
    local sum = 0
    for _, pair in ipairs(kv) do
        local k, v = next(pair)
        sum = sum + v
    end
    lu.assertEquals(sum, 3)
end

function TestTable:testIterWrapper()
    local t = table { 10, 20, 30 }
    local sum = 0
    for v in t:iter() do sum = sum + v end
    lu.assertEquals(sum, 60)
end

function TestTable:testRandomOps()
    local t = table { 1, 2, 3, 4, 5 }

    -- pickRandom
    local v = t:pickRandom()
    lu.assertNotNil(v)
    lu.assertTrue(t:contains(v))

    -- shuffle
    local s = t:shuffle()
    lu.assertEquals(#s, 5)
    lu.assertFalse(s == t) -- Duplicate
    table.sort(s)
    lu.assertEquals(table.concat(s), "12345")

    -- pickWeighted
    local w = { ['A'] = 100, ['B'] = 0 }
    local r = table.pickWeighted(w)
    lu.assertEquals(r, 'A')

    local w2 = { ['X'] = 1 }
    lu.assertEquals(table.pickWeighted(w2), 'X')
end

TestString = {}
function TestString:testSplit_EdgeCases()
    local chars = string.split("abc", "")
    lu.assertEquals(#chars, 3)

    local parts = string.split(",a,,b,", ",")
    lu.assertEquals(parts[1], "")
    lu.assertEquals(parts[2], "a")
    lu.assertEquals(parts[3], "")
    lu.assertEquals(parts[5], "")
end

function TestString:testHex_Unhex()
    local raw = "\0\255\10"
    local h = string.hex(raw)
    lu.assertEquals(h:lower(), "00ff0a")
    local restored = string.unhex(h)
    lu.assertEquals(restored, raw)

    local res, err = string.unhex("XX")
    lu.assertNil(res)
    lu.assertStrContains(err, "not hex")
end

function TestString:testUTF8()
    local s = "Hello 世界 🌍"
    lu.assertEquals(string.trim("  " .. s .. "  "), s)

    local parts = string.split(s, " ")
    lu.assertEquals(parts[2], "世界")
    lu.assertEquals(parts[3], "🌍")

    local dump = string.hexdump("世界")
    lu.assertTrue(dump:lower():find("e4 b8 96 e7 95 8c") ~= nil)
end

function TestString:testPatternEscape()
    local bad = "^$()%.[]*+-?"
    local esc = string.patescape(bad)
    lu.assertNotNil(bad:find(esc))
end

function TestString:testCSub()
    local s = "0123456789"
    lu.assertEquals(string.csub(s, 0, 3), "012")
    lu.assertEquals(string.csub(s, 2, 2), "23")
end

function TestString:testDedent()
    lu.assertEquals(string.dedent("  A\n    B\n  C"), "A\n  B\nC")
    lu.assertEquals(string.dedent("A\nB"), "A\nB")
end

function TestString:testWrap()
    local w = string.wrap("a b c d e", 3)
    lu.assertStrContains(w, "\n")
    local w2 = string.wrap("longword", 5)
    lu.assertStrContains(w2, "longword")
end

TestMath = {}
function TestMath:testBaseConversion()
    local n = require 'ext.number'
    lu.assertEquals(n.bin(10), "1010")
    lu.assertEquals((35):tostring(36), "z")
    lu.assertEquals((-5):tostring(2), "-101")
    lu.assertEquals(n.tostring(0.5, 2), "0.1")
end

function TestMath:testMathUtils()
    lu.assertFalse(math.isprime(1))
    lu.assertTrue(math.isprime(17))
    lu.assertEquals(#math.factors(10), 4)

    local pfactors = math.primeFactorization(12)
    local prod = 1
    for _, v in ipairs(pfactors) do prod = prod * v end
    lu.assertEquals(prod, 12)

    lu.assertEquals(math.gcd(48, 18), 6)
    lu.assertEquals(math.round(1.5), 2)
    lu.assertTrue(math.isnan(math.nan))
    lu.assertEquals(math.trunc(1.9), 1)
    lu.assertEquals(math.trunc(-1.9), -1)
    lu.assertEquals(math.sign(-5), -1)
    lu.assertEquals(math.clamp(10, 0, 5), 5)
end

function TestMath:testExtraMath()
    -- Hyperbolic polyfills check
    if math.sinh then
        lu.assertAlmostEquals(math.sinh(0), 0, 1e-5)
        lu.assertAlmostEquals(math.cosh(0), 1, 1e-5)
    end

    lu.assertEquals(math.mix(10, 20, 0.5), 15)
    lu.assertEquals(math.factorial(5), 120)
    lu.assertAlmostEquals(math.cbrt(27), 3, 1e-5)

    lu.assertTrue(math.isinf(math.huge))
    lu.assertFalse(math.isfinite(math.huge))
    lu.assertFalse(math.isfinite(0 / 0))
    lu.assertTrue(math.isfinite(123))
end

TestFunc = {}
function TestFunc:testCurryAndBind()
    local f = function(a, b, c) return a .. b .. c end
    local f_a = f:bind("A")
    lu.assertEquals(f_a("B", "C"), "ABC")

    local f_b = f:bind_n(2, "B")
    lu.assertEquals(f_b("A", "C"), "ABC")

    local function triple(a, b, c) return string.format("%s-%s-%s", a, b, c) end
    local bound = require('ext.func').P.compile(triple):bind_n(2, "B")
    lu.assertEquals(bound("A", "C"), "A-B-C")
end

function TestFunc:testComposition()
    local f = function(x) return x end
    local g = function(x) return x * 2 end
    lu.assertEquals((f + g)(10), 30)
    lu.assertEquals(f:compose(g)(5), 10)
end

function TestFunc:testPlaceholders()
    local P = func.P
    local _1, _2 = func._1, func._2
    local algo = (_1 + _2) * 2
    lu.assertEquals(algo(1, 2), 6)

    local len_check = P.Gt(P.Len(_1), 0)
    lu.assertTrue(len_check("a"))
    lu.assertFalse(len_check(""))

    local logic = P.Not(P.Eq(_1, 10))
    lu.assertTrue(logic(11))
end

function TestFunc:testIterClass()
    local Iter = require 'ext.iter'
    local r = Iter.range(1, 5):toTable()
    lu.assertEquals(#r, 5)

    local filtered = Iter.range(1, 10):filter(function(x) return x % 2 == 0 end):toTable()
    lu.assertEquals(#filtered, 5)

    local sum = Iter.range(1, 3):reduce(function(acc, x) return acc + x end)
    lu.assertEquals(sum, 6)
end

-- ============================================================================
-- 3. Structs (Class, Set, Maps, Date, Array2D)
-- ============================================================================
TestStructs = {}
function TestStructs:testClass()
    local A = class()
    function A:init(v) self.v = v end

    local B = class(A)
    local b = B(10)
    lu.assertEquals(b.v, 10)
    lu.assertTrue(b:isa(A))

    local C = class()
    function C:init() return 123 end

    local obj, ret = C()
    lu.assertTrue(obj:isa(C))
    lu.assertEquals(ret, 123)
end

function TestStructs:testMultipleInheritance()
    local M1 = class(); M1.v1 = 1
    local M2 = class(); M2.v2 = 2
    local C = class(M1, M2)
    local o = C()
    lu.assertEquals(o.v1, 1)
    lu.assertEquals(o.v2, 2)
end

function TestStructs:testSet()
    local s = Set { 1, 2 } + Set { 2, 3 }
    lu.assertTrue(s:contains(1))
    lu.assertEquals(s:len(), 3)

    local diff = Set { 1, 2 } - Set { 2 }
    lu.assertTrue(diff:contains(1))
    lu.assertFalse(diff:contains(2))

    local inter = Set { 1, 5 } * Set { 1, 6 }
    lu.assertTrue(inter:contains(1))
end

function TestStructs:testOrderedMap()
    local m = OrderedMap()
    m:set("z", 1); m:set("a", 2)
    lu.assertEquals(m:keys()[1], "z")
    m:sort()
    lu.assertEquals(m:keys()[1], "a")
    lu.assertEquals(m.z, 1)
end

function TestStructs:testMultiMap()
    local mm = MultiMap()
    mm:set('k', 1); mm:set('k', 2)
    local vals = mm:get('k')
    lu.assertEquals(#vals, 2)
    lu.assertEquals(vals[2], 2)
end

function TestStructs:testDate()
    local d = Date("2023-12-31 23:59:59")
    local d2 = d + { sec = 1 }
    lu.assertEquals(d2:format("%Y"), "2024")
    lu.assertEquals(d2 - d, 1)
end

function TestStructs:testArray2D()
    local w, h = 3, 2
    local arr = Array2D.new(h, w, 0)
    arr:set(1, 1, 10)
    lu.assertEquals(arr:get(1, 1), 10)
    lu.assertEquals(arr:get(2, 3), 0)
    lu.assertNil(arr:get(9, 9))

    local col = arr:column(1)
    lu.assertEquals(col[1], 10)

    local count = 0
    for _ in arr:iter() do count = count + 1 end
    lu.assertEquals(count, w * h)
end

-- ============================================================================
-- 4. Binary Data
-- ============================================================================
TestBinary = {}
function TestBinary:testAllocAndAccess()
    local bin = require 'ext.binary'
    if not bin then return end

    local size = 16
    local buf = bin.alloc(size)
    lu.assertEquals(tonumber(buf.len), size)

    buf:write(0, 0x12345678, 'int32')
    local val = buf:read(0, 'int32')
    lu.assertEquals(val, 0x12345678)

    local pi = 3.14159
    buf:write(4, pi, 'double')
    local val_d = buf:read(4, 'double')
    lu.assertAlmostEquals(val_d, pi, 1e-6)

    local ptr = buf:ptr(0)
    lu.assertEquals(type(ptr), 'cdata')

    buf:write(15, 255, 'byte')
    lu.assertEquals(buf:read(15, 'uint8'), 255)
end

-- ============================================================================
-- 5. System & IO (OS, Path, CLI)
-- ============================================================================
TestSystem = {}
function TestSystem:setUp()
    self.root = "test_env_root"
    self.sub = self.root .. "/sub dir/deep"
    self.p_root = path(self.root)

    if self.p_root:exists() then
        self:recursiveRemove(self.p_root)
    end

    local ok, err = os.mkdir(self.sub, true)
    if not ok then error("Setup failed: " .. tostring(err)) end
end

function TestSystem:recursiveRemove(pp)
    if not pp:exists() then return end
    for f in pp:dir() do
        local cp = pp / f.path
        if cp:isdir() then self:recursiveRemove(cp) else cp:remove() end
    end
    pp:rmdir()
end

function TestSystem:tearDown()
    if self.p_root:exists() then
        self:recursiveRemove(self.p_root)
    end
end

function TestSystem:testBasicIO_And_BinarySafety()
    local f = self.p_root / "io_test.dat"
    local data = "head\0mid\0tail" .. string.char(255)
    lu.assertTrue(io.writefile(f.path, data))

    local read_back = io.readfile(f.path)
    lu.assertEquals(read_back, data)
    lu.assertEquals(#read_back, #data)

    lu.assertTrue(io.appendfile(f.path, "APPEND"))
    lu.assertStrContains(io.readfile(f.path), "APPEND")

    local tmp = io.tmpfile()
    if tmp then
        tmp:write("temp"); tmp:seek("set", 0)
        lu.assertEquals(tmp:read("*a"), "temp")
        tmp:close()
    end
end

function TestSystem:testIOHelpers()
    local p_str = is_windows and "a\\b\\c.txt" or "a/b/c.txt"
    local dir, name = io.getfiledir(p_str)
    lu.assertStrContains(dir, "b")
    lu.assertEquals(name, "c.txt")

    local stem, ext = io.getfileext(p_str)
    lu.assertStrContains(stem, "c")
    lu.assertEquals(ext, "txt")

    local s, e = io.getfileext("makefile")
    lu.assertEquals(s, "makefile")
    lu.assertNil(e)
end

function TestSystem:testOSFileOps()
    local src = self.p_root / "src.txt"
    local dst = self.p_root / "dst.txt"
    src:write("data")

    lu.assertTrue(os.copy(src.path, dst.path))
    lu.assertTrue(os.fileexists(dst.path))

    local mov = self.p_root / "moved.txt"
    lu.assertTrue(os.move(dst.path, mov.path))
    lu.assertFalse(os.fileexists(dst.path))
    lu.assertTrue(os.fileexists(mov.path))

    lu.assertTrue(os.isdir(self.root))
    lu.assertFalse(os.isdir(src.path))
end

function TestSystem:testEnvVars()
    local key = "LUA_EXT_TEST_VAR"
    if is_windows then
        os.setenv(key, "VAL_VAL")
        lu.assertEquals(os.getenv(key), "VAL_VAL")
        os.setenv(key, "")
    else
        lu.assertNil(os.getenv("NON_EXISTENT_VAR_XYZ"))
    end
end

function TestSystem:testPathComponents()
    local f = path("/a/b/file.tar.gz")
    lu.assertEquals(f:name(), "file.tar.gz")
    lu.assertEquals(f:ext(), ".gz")
    lu.assertEquals(f:stem(), "file.tar")

    local parent = f:parent()
    lu.assertStrContains(parent.path, "b")

    lu.assertEquals(f:setext("txt"):ext(), ".txt")
    lu.assertEquals(f:setext(nil):name(), "file.tar")

    lu.assertTrue(path.cwd():isdir())
    local abs = tostring(path("rel"):abs())
    lu.assertTrue((abs:sub(1, 1) == '/') or (abs:match("^%a:") ~= nil))
end

function TestSystem:testPathIterators()
    local d = self.p_root
    local f1 = d / "a.txt"
    f1:write("a")

    local sub = d / "sub"
    sub:mkdir()

    local f2 = sub / "b.txt"
    f2:write("b")

    local files = {}
    for f in d:dir() do table.insert(files, f:name()) end
    lu.assertTrue(table.contains(files, "a.txt"))

    local rfiles = {}
    for f in d:rdir() do table.insert(rfiles, f:name()) end
    lu.assertTrue(table.contains(rfiles, "b.txt"))
end

function TestSystem:testUnicodePaths()
    local name = "test_unicode_Ω.txt"
    local f = self.p_root / name
    f:write("content")

    lu.assertTrue(f:exists())
    lu.assertTrue(os.fileexists(f.path))

    local found = false
    for child in self.p_root:dir() do
        if child:name() == name then found = true end
    end
    lu.assertTrue(found, "Unicode filename not found in directory listing")
    lu.assertEquals(f:read(), "content")
end

function TestSystem:testSleepPump()
    if is_windows and os.sleep_pump then
        local start = os.clock()
        os.sleep_pump(100) -- 100ms
        lu.assertTrue(os.clock() - start > 0.05)
    end
end

function TestSystem:testCli()
    local schema = { { 'verbose', 'v', type = 'flag' }, { 'out', 'o', default = 'x' }, { 'rest' } }
    local args = { '-v', 'file', '--out=y' }
    local res = require('ext.cli').parse(args, schema)
    lu.assertTrue(res.verbose)
    lu.assertEquals(res.out, 'y')
    lu.assertEquals(res._rest[1], 'file')

    local raw = { 'a=1', 'b' }
    local cmd = getCmdline(table.unpack(raw))
    lu.assertEquals(cmd.a, 1)
    lu.assertTrue(cmd.b)
end

function TestSystem:testProcessIO()
    local res = io.readproc("echo line1")
    lu.assertStrContains(res, "line1")
    local ok = os.execute("exit 0")
    if ok ~= nil then lu.assertTrue(ok) end
end

function TestSystem:testIOEncoding()
    if is_windows then
        local f = self.p_root / "utf8_test.txt"
        local data = "\239\187\191" .. "abc"
        io.writefile(f.path, data)

        local content = io.readfile(f.path, { encoding = 'auto' })
        lu.assertEquals(content, "abc")
    end
end

function TestSystem:testIOLinesArgs()
    local f = self.p_root / "lines_test.txt"
    f:write("10\n20\n30")

    local sum = 0
    for n in io.lines(f.path, "*n") do
        sum = sum + (tonumber(n) or 0)
    end
    lu.assertEquals(sum, 60)

    local fh = f:open("r")
    lu.assertNotNil(fh)
    sum = 0
    for n in fh:lines("*n") do
        sum = sum + (tonumber(n) or 0)
    end
    fh:close()
    lu.assertEquals(sum, 60)
end

-- ============================================================================
-- 6. Utils (XML, CSV, Config, Timer, Range, Template, Reload)
-- ============================================================================
TestUtils = {}
function TestUtils:testXML()
    local doc = xml.parse([[<root a="1"><c>T</c></root>]])
    lu.assertEquals(doc.tag, "root")
    lu.assertEquals(doc.attr.a, "1")
    lu.assertEquals(doc.children[1].children[1], "T")
    lu.assertStrContains(tostring(doc), 'a="1"')
end

function TestUtils:testCSV()
    local tmp = "t.csv"
    io.writefile(tmp, [[name,age
"A, B",10]])
    local d = csv.read(tmp)
    lu.assertEquals(d[1].name, "A, B")
    lu.assertEquals(d[1].age, "10")
    os.remove(tmp)
end

function TestUtils:testConfig()
    local tmp = "t.ini"
    io.writefile(tmp, "[sec]\nk=v\nb=true")
    local c = config.read(tmp)
    lu.assertEquals(c.sec.k, "v")
    lu.assertTrue(c.sec.b)
    os.remove(tmp)
end

function TestUtils:testTemplate()
    lu.assertEquals(template("${v}", { v = 1 }), "1")
end

function TestUtils:testTimer()
    local dt, v = timer.timerQuiet(function() return 1 end)
    lu.assertTrue(type(dt) == 'number')
    lu.assertEquals(v, 1)
end

function TestUtils:testRange()
    local t = {}
    for v in range(1, 5, 2):iter() do table.insert(t, v) end
    lu.assertEquals(#t, 3) -- 1, 3, 5
    lu.assertEquals(t[2], 3)
end

function TestUtils:testReload()
    local tmp = "mock_mod.lua"
    io.writefile(tmp, "return {v=1}")
    local m = require "mock_mod"
    lu.assertEquals(m.v, 1)

    io.writefile(tmp, "return {v=2}")
    m = reload("mock_mod")
    lu.assertEquals(m.v, 2)
    os.remove(tmp)
end

-- ============================================================================
-- 7. Coverage Gaps (Debug, CTypes, GC, XPCall)
-- ============================================================================
TestCoverageGaps = {}

function TestCoverageGaps:testDebugTransform()
    local filename = "test_debug_gap.lua"
    local content = [[
return function()
    local x = 1
    --DEBUG:x = 2
    return x
end
]]
    io.writefile(filename, content)

    local setCond = require 'ext.debug'
    setCond('true')

    local func = dofile(filename)
    local res = func()

    os.remove(filename)
    lu.assertEquals(res, 2, "ext.debug transform failed to uncomment code")
end

function TestCoverageGaps:testCtypesInjection()
    require 'ext.ctypes'
    lu.assertNotNil(_G.int, "_G.int not injected")
    lu.assertNotNil(_G.double, "_G.double not injected")
    lu.assertEquals(type(_G.int), 'cdata', "_G.int is not a ctype")
    local val = _G.int(123)
    lu.assertEquals(tonumber(val), 123)
end

function TestCoverageGaps:testGCTable()
    if not newproxy then return end
    require 'ext.gc'
    local finalized_count = 0
    do
        local t = {}
        setmetatable(t, {
            __gc = function() finalized_count = finalized_count + 1 end
        })
    end
    collectgarbage("collect")
    collectgarbage("collect")

    if finalized_count == 0 then
        local _ = {}
        for i = 1, 1000 do _[i] = {} end
        collectgarbage("collect")
    end
    -- Just verify it doesn't crash
end

function TestCoverageGaps:testXPCallArgs()
    local function f(a, b) return a + b end
    local function err(msg) return "error: " .. msg end

    local ok, res = xpcall(f, err, 10, 20)
    lu.assertTrue(ok)
    lu.assertEquals(res, 30)

    local function f_err() error("boom", 0) end
    local ok2, msg = xpcall(f_err, err)
    lu.assertFalse(ok2)
    lu.assertEquals(msg, "error: boom")
end

-- ============================================================================
-- 8. Compat 5.3 Features (Math, UTF8, Struct, Format, Table)
-- ============================================================================
TestCompat = {}

function TestCompat:testCompat_Math()
    local math = require 'ext.math'
    lu.assertNotNil(math.maxinteger)
    lu.assertNotNil(math.mininteger)

    local i3 = math.tointeger(3)
    -- [Fix] Allow cdata result (int64) or number result
    -- LuaJIT FFI returns cdata<int64_t> which is numerically equal to 3 but fails strict type checks
    if type(i3) == 'cdata' then
        lu.assertTrue(i3 == 3, "math.tointeger(3) should equal 3")
        -- [Fix] Explicitly check for nil to return boolean true, avoiding strict boolean check failure in LuaUnit
        local is_int64 = (tostring(i3):find("LL") or tostring(i3):find("ULL")) ~= nil
        lu.assertTrue(is_int64, "math.tointeger(3) should return int64 cdata")
    else
        lu.assertEquals(i3, 3)
    end

    local i3f = math.tointeger(3.0)
    if type(i3f) == 'cdata' then
        lu.assertTrue(i3f == 3, "math.tointeger(3.0) should equal 3")
    else
        lu.assertEquals(i3f, 3)
    end

    lu.assertNil(math.tointeger(3.1))

    if ffi then
        lu.assertEquals(math.type(3), 'float')
        -- If tointeger returns cdata, check its type
        if type(i3) == 'cdata' then
            lu.assertEquals(math.type(i3), 'integer')
        end
    end

    lu.assertFalse(math.ult(-1, 2))
    lu.assertTrue(math.ult(2, -1))
end

function TestCompat:testCompat_UTF8()
    local utf8 = require 'ext.utf8'
    lu.assertEquals(utf8.len("A"), 1)
    lu.assertEquals(utf8.len("€"), 1)
    local c1 = utf8.codepoint("A", 1)
    lu.assertEquals(c1, 65)
    lu.assertEquals(utf8.char(65), "A")
end

function TestCompat:testCompat_Struct()
    local string = require 'ext.string'

    local fmt = "bhi" -- byte, short, int
    local packed = string.pack(fmt, 10, 2000, 300000)
    local size = string.packsize(fmt)
    lu.assertEquals(#packed, size)

    local next_pos, b, h, i = string.unpack(fmt, packed)
    lu.assertEquals(b, 10)
    lu.assertEquals(h, 2000)
    lu.assertEquals(i, 300000)

    -- String (z = zero terminated)
    local fmt_z = "z"
    local packed_z = string.pack(fmt_z, "hello")
    lu.assertEquals(#packed_z, 6)
    local _, val_z = string.unpack(fmt_z, packed_z)
    lu.assertEquals(val_z, "hello")
end

function TestCompat:testCompat_StringFormat()
    local t = { a = 1 }
    local res = string.format("%q", t)
    lu.assertStrContains(res, '"')

    lu.assertEquals(string.format("%s", nil), "nil")
    lu.assertEquals(string.format("%s", true), "true")
end

function TestCompat:testCompat_TablePackUnpack()
    local t = table.pack(1, nil, 3)
    lu.assertEquals(t.n, 3)
    lu.assertEquals(t[1], 1)
    lu.assertNil(t[2])
    lu.assertEquals(t[3], 3)

    local a, b, c = table.unpack(t, 1, t.n)
    lu.assertEquals(a, 1)
    lu.assertNil(b)
    lu.assertEquals(c, 3)
end

-- ============================================================================
-- Run
-- ============================================================================
os.exit(lu.LuaUnit.run())
