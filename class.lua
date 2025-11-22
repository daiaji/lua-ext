local table = require 'ext.table'

-- classes

local function newmember(class, ...)
	local obj = setmetatable({}, class)
	if obj.init then return obj, obj:init(...) end
	return obj
end

local classmeta = {
	__call = function(self, ...)
-- [[ normally:
		return self:new(...)
--]]
--[[ if you want to keep track of all instances
		local results = table.pack(self:new(...))
		local obj = results[1]
		self.instances[obj] = true
		return results:unpack()
--]]
	end,
}

-- usage: class:isa(obj)
--  so it's not really a member method, since the object doesn't come first, but this way we can use it as Class:isa(obj) and not worry about nils or local closures
local function isa(self, arg)
	-- Check if self is a Class or an Instance
	-- In this class system, classes have cl.class == cl (set in class() function)
	-- Instances are setmetatable({}, cl), so instance.class resolves to cl.
	-- Thus instance.class == instance is false (cl != instance).
	local selfIsClass = (self.class == self)
	
	if selfIsClass then
		-- Usage: Class:isa(obj) -> isa(Class, obj)
		-- Check if obj is instance of Class
		if type(arg) ~= 'table' then return false end
		if not arg.isaSet then return false end
		return arg.isaSet[self] or false
	else
		-- Usage: obj:isa(Class) -> isa(obj, Class)
		-- Check if obj (self) is instance of Class (arg)
		-- self.isaSet contains all ancestors
		if not self.isaSet then return false end
		return self.isaSet[arg] or false
	end
end

local function class(...)
	local cl = table(...)
	cl.class = cl

	cl.super = ...	-- .super only stores the first.  the rest can be accessed by iterating .isaSet's keys

	-- I was thinking of calling this '.superSet', but it is used for 'isa' which is true for its own class, so this is 'isaSet'
	cl.isaSet = {[cl] = true}
	for i=1,select('#', ...) do
		local parent = select(i, ...)
		if parent ~= nil then
			cl.isaSet[parent] = true
			if parent.isaSet then
				for grandparent,_ in pairs(parent.isaSet) do
					cl.isaSet[grandparent] = true
				end
			end
		end
	end

	-- store 'descendantSet' as well that gets appended when we call class() on this obj?
	for ancestor,_ in pairs(cl.isaSet) do
		ancestor.descendantSet = ancestor.descendantSet or {}
		ancestor.descendantSet[cl] = true
	end

	cl.__index = cl
	cl.new = newmember
	cl.isa = isa	-- usage: Class:isa(obj)
	cl.subclass = class     -- such that cl:subclass() or cl:subclass{...} will return a subclass of 'cl'

--[[ if you want to keep track of all instances
	cl.instances = setmetatable({}, {__mode = 'k'})
--]]

	setmetatable(cl, classmeta)
	return cl
end

return class