--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Services //--
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--// Contants //--
local native_env = getfenv()

local client, server, studio = RunService:IsClient(), RunService:IsServer(), RunService:IsStudio()

local context = client and "client" or "server"
local _context = client and "server" or "client"

local Context = client and "Client" or "Server"

local Manifest = script:WaitForChild("Manifest")
local manifest = Manifest:GetAttributes()
if client then Manifest:Destroy() end
table.freeze(manifest)

local optimize_production = not studio and manifest.OptimizeProduction

--// Storage //--
local instance_registry = {}
local name_registry = {}
local calls_registry = {}

local execution_queue = {}

local service_registry = {}

local universe = {}
universe.universe = universe
local decorators = {}

--// Private //--
local function _scan<V>(condition: V, message: string?): V
	if condition ~= false then
		local NetworkService = service_registry["NetworkService"]
		if NetworkService then
			NetworkService:IncrementOffset(1)
		end

		if studio then
			error(`Exploit detected: {message or "unknown reason"}.`)
		end
	end

	return condition
end

local function _content_json(json: string?, contextify: boolean?): { [any]: any }
	if not json then return {} end

	local content = HttpService:JSONDecode(json)
	if contextify then
		local items_to_append = {}

		for _, data: { string | any } in content do
			if data[1] == context then
				local children = data[3] or data[2]
				if type(children) == "table" then
					for _, ctx_decorator in children do
						if type(ctx_decorator) == "table" and type(ctx_decorator[1]) == "string" then
							table.insert(items_to_append, ctx_decorator)
						end
					end
				end
			end
		end

		for _, item in items_to_append do
			table.insert(content, item)
		end
	end

	return table.freeze(content)
end

local function _for_each(tbl: { any? }, func: (...any) -> (), ...): ()
	for _, item: any in tbl do
		func(item, ...)
	end
end

local function _clear_attributes(instance: Instance): { [any]: any }
	if not client then return end

	local attributes = instance:GetAttributes()

	for attribute, _ in attributes do
		instance:SetAttribute(attribute, nil)
	end

	return attributes
end

local function _has_decorator(ancestor: any, name: string): boolean
	if type(ancestor) == "table" and ancestor.Ancestors then
		for _, decorator in ancestor.Ancestors do
			if decorator[1] == name then
				return true
			end
		end
	elseif type(ancestor) == "table" then
		for _, decorator in ancestor do
			if decorator[1] == name then
				return true
			end
		end
	end
	return false
end

-- Maby change to always return a table, could simplfy some check for some nano
local function _get_decorator_args(list: {any}, name: string): {any}?
	for _, data in list do
		if data[1] == name then
			return data[2] or {}
		end
	end

	return nil
end

local function _order_by_priority<I>(instances: { I }, priority_required: boolean): { I }
	local ordered = table.create(#instances)
	local priority_cache = {}

	for _, instance: Instance in instances do
		local priority = instance:GetAttribute("Priority" .. Context)

		if not priority then
			local header = _content_json(instance:GetAttribute("ContentHeader"), true)
			if header then
				local args = _get_decorator_args(header, "priority")
				priority = args and args[1]
			end
		end

		if not priority then
			priority = instance:GetAttribute("ResolvedPriority")
		end

		if priority_required and not priority then continue end

		table.insert(ordered, instance)
		priority_cache[instance] = priority or math.huge
	end

	table.sort(ordered, function(a: any, b: any)
		return priority_cache[a] < priority_cache[b]
	end)

	return ordered
end

--// Proxy //--
local Proxy = {}

Proxy.__setmetatable = function(self: Proxy, new_meta): Proxy
	rawset(self, "metatable", new_meta)
	return self
end

Proxy.__getmetatable = function(self)
	return rawget(self, "metatable")
end

Proxy.__type = function(self)
	return "<"..universe.typeof(self.object)..">"
end

Proxy.__index = function(self, index: any)
	local metatable = rawget(self, "metatable")
	if metatable and metatable.__index then
		if type(metatable.__index) == "function" then
			local result = metatable.__index(self, index)

			if result ~= nil then
				return result
			end
		elseif type(metatable.__index) == "table" then
			if metatable.__index[index] ~= nil then
				return metatable.__index[index]
			end
		end
	end

	local extended = rawget(self, "extended")
	if extended[index] ~= nil then
		return extended[index]
	end

	local success, value = pcall(function()
		return self.object[index]
	end)

	if success then
		if typeof(value) == "function" then
			return function(...)
				if select(1, ...) == self then
					return value(self.object, select(2, ...))
				end

				return value(...)
			end
		end

		return value
	end
end

Proxy.__newindex = function(self, index: any, value: any)
	local metatable = rawget(self, "metatable")
	if metatable and metatable.__newindex then
		if type(metatable.__newindex) == "function" then
			metatable.__newindex(self, index, value)
			return
		end
	end

	local success = pcall(function()
		self.object[index] = value
	end)

	if not success then
		rawget(self, "extended")[index] = value
	end
end

function Proxy.new(object: any?, force: boolean?): Proxy
	if not force and type(object) == "table" and getmetatable(object) == Proxy then
		return object
	end

	local self = {
		object = object,
		extended = {}
	}

	return setmetatable(self, Proxy)
end

--// Usage Resolution //--
local function _get_usage(class_name: string, method_name: string, stack_level: number?): boolean?
	local current_source = debug.info(1, "s")
	local match1 = class_name .. "." .. method_name
	local match2 = class_name .. ":" .. method_name

	local start_level = stack_level or 3
	local max_level = stack_level and stack_level or 8

	for level = start_level, max_level do
		local s, l = debug.info(level, "sl")
		if not s or not l then break end
		if s == current_source then continue end

		local caller_source = type(s) == "string" and string.sub(s, 1, 1) == "=" and string.sub(s, 2) or s
		local clean_source = string.match(caller_source, '^%[string "(.-)"%]$') or caller_source
		local short_source = string.match(clean_source, "([%w_]+)$")

		local caller_calls = calls_registry[clean_source] or calls_registry[caller_source]
		if not caller_calls and short_source then
			caller_calls = calls_registry[short_source]
		end

		if caller_calls then
			local line_calls = caller_calls[l] or caller_calls[tostring(l)]
			if line_calls then
				local data = line_calls[match1] or line_calls[match2]
				if not data then
					for callName, callData in line_calls do
						if string.match(callName, "[:%.]" .. method_name .. "$") or callName == method_name then
							data = callData
							break
						end
					end
				end

				if data ~= nil then
					return (data == true or data.captured == true)
				end
			end

			return nil
		end

		if short_source and name_registry[short_source] then
			break
		end
	end

	return nil
end

--// Collected Item //--
local CollectedItem = {}
CollectedItem.__type = "CollectedItem"

CollectedItem.__index = function(self, key)
	if key == "modules" then
		return self[1] or {}
	elseif key == "services" then
		return self[2] or {}
	elseif key == "method" then
		return self[3] or ""
	elseif key == "access" then
		return self[4] or "."
	elseif key == "exports" then
		return self[5] or {}
	elseif key == "args" then
		local args = rawget(self, "_args")
		if not args then
			args = { table.unpack(self, 6) }
			rawset(self, "_args", args)
		end
		return args
	elseif key == "raw" then
		return self
	elseif CollectedItem[key] ~= nil then
		return CollectedItem[key]
	end
	return nil
end

function CollectedItem:Resolve(targetName: string?)
	local name = targetName or self.services[1] or self.modules[1]
	if not name then return nil end

	if (not targetName or targetName == self.services[1]) and #self.services > 0 then
		return universe.game:GetService(name)
	end

	return universe.game:GetModule(name) or universe.game:GetService(name)
end

function CollectedItem:GetUsage(stackLevel: number?, targetName: string?): boolean?
	local target = targetName or self.services[1] or self.modules[1]
	if not target then return nil end

	local level = stackLevel and (stackLevel + 1) or 4
	return _get_usage(target, self.method, level)
end

local function wrapCollectedEntry(entry: any)
	if type(entry) == "table" and getmetatable(entry) ~= CollectedItem then
		setmetatable(entry, CollectedItem)
	end
	return entry
end

local function wrapCollectedList(list: any)
	if type(list) == "table" then
		for _, entry in list do
			wrapCollectedEntry(entry)
		end
	end
	return list
end

--// Virtual //--
local Node = {}
Node.__type = "Node"

Node.__index = function(self, index: string): any?
	if Node[index] ~= nil then
		return Node[index]
	end

	local success, value = pcall(function()
		return self.Instance[index]
	end)

	if success then
		if typeof(value) == "function" then
			return function(_, ...)
				return value(self.Instance, ...)
			end
		end

		return value
	end

	return self:FindFirstChild(index)
end

Node.__newindex = function(self: Node, key: any, value: any)
	if rawget(self, "Locked") then return end --// KINDA USELESS BUT WHATEVER

	local success = pcall(function()
		self.Instance[key] = value
	end)

	if not success then
		rawset(self, key, value)
	end
end

Node.__unpack = function(self): Instance
	return self.Instance
end

Node.__tostring = function(self): string
	return tostring(self.Instance)
end

function Node.new(ancestor: Node | Instance, instance: Instance?, childen: { Node | Instance }?): Node
	if not instance then
		instance = ancestor
		ancestor = nil
	end

	local self = {}

	self.Instance = instance

	self.Children = childen or {}
	self.Parent = ancestor or instance.Parent

	self.Name = instance.Name

	if optimize_production then
		self.FullName = ""
	else
		if type(ancestor) == "table" and ancestor.FullName then
			self.FullName = ancestor.FullName .. "." .. instance.Name
		else
			self.FullName = instance:GetFullName()
		end
	end

	self.Attributes = instance:GetAttributes()

	if ancestor then
		table.insert(ancestor.Children, self)
	end

	return setmetatable(self, Node)
end

-- TODO fix, not really a deep clone
function Node:Clone(): ()
	local instance = self.Instance:Clone()
	instance.Name = self.Name

	return instance
end

function Node:SetAttribute(attribute: string, value: any?)
	self.Attributes[attribute] = value
end

function Node:GetAttribute(attribute: string): any?
	return self.Attributes[attribute]
end

function Node:GetAttributes(): {[string]: any}
	return self.Attributes
end

function Node:GetCollected(decoratorName: string?): any
	if not self.Collected then
		local rawPayload = self.Attributes and self.Attributes.ContentPayload
		if not rawPayload and self.Instance and typeof(self.Instance) == "Instance" then
			pcall(function()
				rawPayload = self.Instance:GetAttribute("ContentPayload")
			end)
		end
		if rawPayload then
			local payload = _content_json(rawPayload)
			if payload and payload[".collected"] and type(payload[".collected"]) == "table" then
				local wrappedMap = {}
				for decName, list in payload[".collected"] do
					wrappedMap[decName] = wrapCollectedList(list)
				end
				self.Collected = wrappedMap
			end
		end
	end

	local collected = self.Collected or {}
	if decoratorName then
		return collected[decoratorName] or {}
	end
	return collected
end

function Node:GetCalls(sourceOrModule: string?): any
	if not self.Calls then
		local rawPayload = self.Attributes and self.Attributes.ContentPayload
		if not rawPayload and self.Instance and typeof(self.Instance) == "Instance" then
			pcall(function()
				rawPayload = self.Instance:GetAttribute("ContentPayload")
			end)
		end
		if rawPayload then
			local payload = _content_json(rawPayload)
			if payload and payload[".calls"] then
				self.Calls = payload[".calls"]
			end
		end
	end

	local calls = self.Calls or calls_registry
	if sourceOrModule then
		if self.Calls and self.Name == sourceOrModule then
			local firstKey = next(self.Calls)
			if firstKey and (type(firstKey) == "number" or tonumber(firstKey)) then
				return self.Calls
			end
		end

		if calls[sourceOrModule] then
			return calls[sourceOrModule]
		end

		if calls_registry[sourceOrModule] then
			return calls_registry[sourceOrModule]
		end

		return {}
	end
	return calls
end

function Node:GetFullName(): string
	return self.FullName
end

function Node:GetChildren(): { (Node | Instance)? }
	return self.Children
end

function Node:GetDescendants(): { (Node | Instance)? }
	local descendants = {}

	local function recurse(children: { (Node | Instance)? })
		for _, child: Node | Instance in children do
			table.insert(descendants, child)
			recurse(child:GetChildren())
		end
	end

	recurse(self:GetChildren())

	return descendants
end

function Node:FindFirstChild(index: string, recursive: boolean): (Node | Instance)?
	assert(typeof(index) == "string", "argument #1 expects a string, but "..typeof(index).." was passed")

	for _, node: Node in self:GetChildren() do
		if (node.Name == index) then
			return node
		end

		if not recursive then continue end

		local instance = node:FindFirstChild(index, recursive)
		if instance then
			return instance
		end
	end
end

function Node:Destroy(): ()
	for _, child: Node | Instance in self:GetChildren() do
		child:Destroy()
	end

	if typeof(self.Parent) == "table" then
		table.remove(self.Parent.Children, table.find(self.Parent.Children, self))
	end

	self.Instance:Destroy()
	self.Instance = nil

	setmetatable(self, nil)
end

table.freeze(Node)

--// Universe -> Type //--
universe.typeof = function(value: any, ...: any): string?
	local actual_type: string?
	local base_type = type(value)

	if base_type == "table" or base_type == "userdata" then
		local metatable = getmetatable(value)

		if type(metatable) == "table" then
			local custom_type = metatable.__type

			if custom_type then
				if type(custom_type) == "function" then
					actual_type = custom_type(value)
				else
					actual_type = custom_type
				end
			end
		end
	end

	if not actual_type then
		actual_type = typeof(value)
	end

	local accepted_count = select("#", ...)

	if accepted_count == 0 then
		return actual_type
	end

	for i = 1, accepted_count do
		local arg = select(i, ...)

		if type(arg) == "table" then
			if table.find(arg, actual_type) then
				return actual_type
			end
		elseif arg == actual_type then
			return actual_type
		end
	end

	return nil
end

--// Universe -> Metatable //--
universe.setmetatable = function(tbl: dict, mt: dict)
	local metatable = getmetatable(tbl)

	if type(metatable) == "table" and type(metatable.__setmetatable) == "function" then
		return metatable.__setmetatable(tbl, mt)
	end

	return setmetatable(tbl, mt)
end

universe.getmetatable = function(tbl: dict): dict
	local metatable = getmetatable(tbl)

	if type(metatable) == "table" and type(metatable.__getmetatable) == "function" then
		return metatable.__getmetatable(tbl)
	end

	return metatable
end

--// Universe -> Game //--
universe.game = Proxy.new(game)

universe.game.GetNative = function(_, name: string): any?
	return native_env[name]
end

universe.game.GetService = function(_, name: string): any
	if service_registry[name] then
		return service_registry[name]
	end

	local success, native_service = pcall(function()
		return game:GetService(name)
	end)

	if success and native_service then
		return native_service
	end

	return setmetatable({}, {
		__tostring = function(): string
			local custom_service = service_registry[name]
			if custom_service then
				return tostring(custom_service)
			end
			return name
		end,

		__index = function(self, key: any): any?
			local custom_service = service_registry[name]

			if not custom_service then
				universe.error(`attempt to index field '{tostring(key)}' on service '{name}' which has not been registered`, 2)
				return nil
			end

			local value = custom_service[key]

			if type(value) == "function" then
				return function(passed_self, ...)
					if passed_self == self then
						return value(custom_service, ...)
					end

					return value(passed_self, ...)
				end
			end

			return value
		end,

		__newindex = function(_, key: any, value: any): ()
			local custom_service = service_registry[name]

			if not custom_service then
				universe.error(`attempt to assign field '{tostring(key)}' on service '{name}' which has not been registered`, 2)
				return
			end

			custom_service[key] = value
		end
	})
end

universe.game.HasService = function(_, name: string): boolean
	if service_registry[name] then
		return true
	end

	local success, native_service = pcall(function()
		return game:GetService(name)
	end)

	if success and native_service then
		return true
	end

	return false
end

universe.game.GetModule = function(_, name: string): dict?
	local node = name_registry[name]
	if node and node.Content then
		return node.Content
	end

	return setmetatable({}, {
		__tostring = function(): string
			local node = name_registry[name]
			if node and node.Content then
				return tostring(node.Content)
			end
			return name
		end,

		__index = function(self, key: any): any?
			local node = name_registry[name]

			if not node or not node.Content then
				universe.error(`attempt to index field '{tostring(key)}' on module '{name}' which has not been registered`, 2)
				return nil
			end

			local value = node.Content[key]

			if type(value) == "function" then
				return function(passed_self, ...)
					if passed_self == self then
						return value(node.Content, ...)
					end

					return value(passed_self, ...)
				end
			end

			return value
		end,

		__newindex = function(_, key: any, value: any): ()
			local node = name_registry[name]

			if not node or not node.Content then
				universe.error(`attempt to assign field '{tostring(key)}' on module '{name}' which has not been registered`, 2)
				return
			end

			node.Content[key] = value
		end
	})
end

universe.game.HasModule = function(_, name: string, loaded: boolean?): boolean
	local node = name_registry[name]
	if loaded then
		return node ~= nil and node.Content ~= nil
	end
	return node ~= nil
end

universe.game.RegisterService = function(_, name: string, content: dict?): ()
	service_registry[name] = content
end

universe.game.RegisterModule = function(_, name: string, content: dict?): ()
	local node = name_registry[name]
	if not node then
		node = {
			Name = name,
			Content = content,
			Children = {},
			Attributes = {}
		}
		setmetatable(node, Node)
		name_registry[name] = node
	else
		node.Content = content
	end
end

universe.game.RegisterBuiltIn = function(_, name: string, content: dict?): ()
	universe[name] = content
end

universe.game.RegisterDecorator = function(_, name: string, wrapper: (context: any, func: (...any?) -> (...any?), ...any?) -> ((...any?) -> (...any?))?): ()
	decorators[name] = wrapper
end

--// Universe -> Require //--
universe.require = function(module: any): any?
	if type(module) == "string" then
		local node = name_registry[module]
		if node and node.Content then
			return node.Content
		end
		if service_registry[module] then
			return service_registry[module]
		end
	end

	if universe.typeof(module) == "Node" then
		if module.Content then
			return module.Content
		end

		module = module.Instance
	elseif typeof(module) == "Instance" then
		local node = instance_registry[module]
		if node and node.Content then
			return node.Content
		end
		local name_node = name_registry[module.Name]
		if name_node and name_node.Content then
			return name_node.Content
		end
	end

	return require(module)
end

--// Universe -> Newproxy //--
universe.newproxy = function(object: any?, ...): any
	if object == nil or type(object) == "boolean" then
		return newproxy(object)
	end

	return Proxy.new(object, ...)
end

--// Universe -> Output //--
local function _get_trace(level: number): string
	if optimize_production then
		return ""
	end

	local source, line = debug.info(level, "sl")
	if not source then return "" end

	local success, env = pcall(getfenv, level)
	if success and type(env) == "table" and type(env.script) == "table" and type(env.script.GetFullName) == "function" then
		source = env.script:GetFullName()
	elseif type(source) == "string" and string.sub(source, 1, 1) == "=" then
		source = string.sub(source, 2)
	end

	return `{source}:{line or 0}:`
end

universe.print = function(...: any?): ()
	if not studio and manifest.PrivatePrint then return end

	local trace = _get_trace(3)
	if trace ~= "" then
		print(trace, ...)
	else
		print(...)
	end
end

universe.warn = function(...: any?)
	if not studio and manifest.PrivateWarn then return end

	local trace = _get_trace(3)
	if trace ~= "" then
		warn(trace, ...)
	else
		warn(...)
	end
end

universe.error = function(message: string?, level: number?): ()
	if not studio and manifest.PrivateError then
		coroutine.yield()
	end

	error(message, level == 0 and 0 or (level and level + 1 or 2))
end

universe.assert = function<T>(value: T?, message: string?, level: number?): T?
	if not value then
		universe.error(message or "assertion failed!", level == 0 and 0 or (level and level + 1 or 3))
	end

	return value
end

--// Universe -> Debug //--
universe.debug = Proxy.new(debug)

universe.debug.print = print
universe.debug.warn = warn
universe.debug.error = error
universe.debug.assert = assert

--// Decorator Signatures //--
local decorator_signatures = {
	["usages"] = function(_, class_name: string, method_name: string)
		return function()
			return _get_usage(class_name, method_name, 3)
		end
	end
}

--// Decorator Context //--
local DecoratorContext = {}
DecoratorContext.__type = "DecoratorContext"

DecoratorContext.__index = function(self, key)
	if DecoratorContext[key] ~= nil then
		return DecoratorContext[key]
	end
	local ancestors = rawget(self, "Ancestors")
	if type(key) == "number" and ancestors then
		return ancestors[key]
	end
	return nil
end

function DecoratorContext:GetChildren(): { any }
	local children = rawget(self, "_childrenObjects")
	if children then return children end

	local rawChildren = rawget(self, "Children")
	if not rawChildren or #rawChildren == 0 then
		children = {}
		rawset(self, "_childrenObjects", children)
		return children
	end

	children = table.create(#rawChildren)
	for _, childData in rawChildren do
		local childContext = DecoratorContext.new(
			childData[1],
			childData[2] or {},
			self,
			childData[3],
			rawget(self, "Instance"),
			rawget(self, "Method"),
			rawget(self, "Ancestors"),
			rawget(self, "OriginalFunction"),
			rawget(self, "WrappedFunction"),
			rawget(self, "Content")
		)
		table.insert(children, childContext)
	end
	rawset(self, "_childrenObjects", children)
	return children
end

function DecoratorContext:FindFirstChild(name: string): any?
	for _, child in self:GetChildren() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function DecoratorContext:IsDescendantOf(parentName: string): boolean
	local current = rawget(self, "Parent")
	while current do
		if current.Name == parentName then
			return true
		end
		current = rawget(current, "Parent")
	end
	return false
end

function DecoratorContext.new(
	name: string,
	args: { any }?,
	parent: any?,
	children: { any }?,
	instance: any?,
	method: string?,
	ancestors: { any }?,
	originalFunc: any?,
	wrappedFunc: any?,
	content: any?
)
	local self = {
		Name = name,
		Arguments = args or {},
		Parent = parent,
		Children = children,
		Instance = instance,
		Method = method or "",
		Ancestors = ancestors or {},
		OriginalFunction = originalFunc,
		WrappedFunction = wrappedFunc or originalFunc,
		Content = content,
	}
	return setmetatable(self, DecoratorContext)
end

local function _wrap_children(targetFunc: any, childrenList: { any }?, parentContext: any?): any
	if type(targetFunc) ~= "function" then return targetFunc end
	if not childrenList or #childrenList == 0 then return targetFunc end

	local wrapped = targetFunc
	for i = #childrenList, 1, -1 do
		local childData = childrenList[i]
		local childName = childData[1]
		local childArgs = childData[2] or {}
		local childNested = childData[3]

		local wrapper = decorators[childName]
		if wrapper then
			local childContext = DecoratorContext.new(
				childName,
				childArgs,
				parentContext,
				childNested,
				parentContext and parentContext.Instance,
				parentContext and parentContext.Method,
				parentContext and parentContext.Ancestors,
				targetFunc,
				wrapped,
				parentContext and parentContext.Content
			)

			local funcToWrap = wrapped
			if childNested and #childNested > 0 then
				funcToWrap = _wrap_children(wrapped, childNested, childContext)
				childContext.WrappedFunction = funcToWrap
				if funcToWrap == nil then
					return nil
				end
			end

			local result = wrapper(childContext, funcToWrap, table.unpack(childArgs))
			if result == nil then
				return nil
			end
			wrapped = result
		end
	end

	return wrapped
end

--// Decorator -> Context //--
decorators.client = function(context: any, func: (...any?) -> (...any?), value: boolean): ((...any?) -> (...any?))?
	if type(value) ~= "boolean" then return func end

	if client then
		return value == true and func or nil
	else
		return not (value and not _has_decorator(context, "server")) and func or nil
	end
end

decorators.server = function(context: any, func: (...any?) -> (...any?), value: boolean): ((...any?) -> (...any?))?
	if type(value) ~= "boolean" then return func end

	if server then
		return value == true and func or nil
	else
		return not (value and not _has_decorator(context, "client")) and func or nil
	end
end

--// Registering //--
local function _register_module(instance: Instance, node: Node): boolean?
	_clear_attributes(instance)

	if node.Attributes.ContentExcluded then return true end

	local header = _content_json(node.Attributes.ContentHeader, true)
	node.Attributes.ContentHeader = nil

	local ctx_args = _get_decorator_args(header, context)
	local alt_args = _get_decorator_args(header, _context)

	if (ctx_args and ctx_args[1] == false) or (not ctx_args and (alt_args and alt_args[1] == true)) then return true end

	name_registry[node.Name] = node
	instance_registry[instance] = node

	table.insert(execution_queue, node)
end

local function _register_descendants(instance: Instance, ancestor: Node): ()
	local node = ancestor:new(instance)

	if client then
		instance.Name = ""
		instance.Parent = nil
	end

	if instance:IsA("ModuleScript") then
		_register_module(instance, node)
	end

	_for_each(instance:GetChildren(), _register_descendants, node)
end

local function _register_roots(): ()
	local roots = CollectionService:GetTagged(manifest.TagRoot)

	for _, instance: Instance in roots do
		if not instance:GetAttribute("Context" .. Context) then
			continue
		end

		local node = Node.new(instance)

		if client then
			instance.Name = ""
			instance.Parent = nil
		end

		_for_each(instance:GetChildren(), _register_descendants, node)

		if client then
			instance:Destroy()
		end
	end
end

--// Requiring //--
local function _load_registry(): ()
	for index, node: Node in execution_queue do
		local success = true

		if optimize_production then
			require(node.Instance)
		else
			node.Instance.Name = node:GetFullName()
			success = pcall(require, node.Instance)
		end

		if client then
			node.Instance.Name = ""
			node.Instance:Destroy()
			node.Instance = nil
		else
			node.Instance.Name = node.Name
		end

		if not success then
			if client then
				for i = index + 1, #execution_queue do
					local remaining_node = execution_queue[i]
					remaining_node.Instance:Destroy()
					remaining_node.Instance = nil
				end
			end
			coroutine.yield()
		end
	end
end

--// Initializing //--
local function _execute_targets(node: Node, content: any, targets: { [any]: any }, phase: string): ()
	if not targets then return end

	for name: any, _ in targets do
		local func = content[name]

		if type(func) == "function" then
			if optimize_production then
				func()
			else
				local success, result = xpcall(func, debug.traceback, content)

				if not success then
					universe.error(`Error during '{node:GetFullName()}' ({name}) {phase}:\n{result}`, 0)
				end
			end
		end
	end
end

local function _build_content(node: Node, content: any?): ()
	local type_c = type(content)
	if type_c ~= "table" and type_c ~= "userdata" then return end

	local payload = _content_json(node.Attributes.ContentPayload)
	node.Attributes.ContentPayload = nil

	if payload and payload[".collected"] then
		local wrappedMap = {}
		for decName, list in payload[".collected"] do
			wrappedMap[decName] = wrapCollectedList(list)
		end
		node.Collected = wrappedMap
	end

	if payload and payload[".calls"] then
		node.Calls = payload[".calls"]

		local module_source = nil
		if type(content) == "table" then
			for _, v in content do
				if type(v) == "function" then
					local s = debug.info(v, "s")
					module_source = string.sub(s, 1, 1) == "=" and string.sub(s, 2) or s
					break
				end
			end
		end

		for key, value in payload[".calls"] do
			if type(value) == "table" then
				local lineNum = tonumber(key)
				if lineNum then
					calls_registry[node.Name] = calls_registry[node.Name] or {}
					calls_registry[node.Name][lineNum] = value
					if module_source and module_source ~= node.Name then
						calls_registry[module_source] = calls_registry[node.Name]
					end
				elseif not lineNum then
					calls_registry[key] = calls_registry[key] or {}
					for lKey, lVal in value do
						local lNum = tonumber(lKey)
						if lNum then
							calls_registry[key][lNum] = lVal
						end
					end
				end
			end
		end
	end

	local build_targets = { Build = true }
	local init_targets = { Init = true }

	if payload then
		for method_name: string, decorator_list: {[number]: {string | any}} in payload do
			if content[method_name] == nil then continue end

			for i = #decorator_list, 1, -1 do
				local decorator_data: { string | any } = decorator_list[i]
				local decorator_name = decorator_data[1]
				local decorator_args = decorator_data[2] or {}
				local children_data = decorator_data[3]

				-- Support legacy 2-element tuple for context decorators: { "client", nestedMetadata }
				if not children_data and (decorator_name == "client" or decorator_name == "server") then
					if type(decorator_args[1]) == "table" and type(decorator_args[1][1]) == "string" then
						children_data = decorator_args
						decorator_args = { true }
					end
				end

				for j, arg in decorator_args do
					if type(arg) == "table" and type(arg.signature) == "string" and decorator_signatures[arg.signature] then
						decorator_args[j] = decorator_signatures[arg.signature](payload, node.Name, method_name)
					end
				end

				local originalFunc = content[method_name]

				-- Gating check for context decorators (@client / @server) before wrapping children:
				-- If the method is not allowed in this context, strip it immediately without running children.
				if decorator_name == "client" or decorator_name == "server" then
					local wrapper = decorators[decorator_name]
					if wrapper and wrapper(decorator_list, originalFunc, table.unpack(decorator_args)) == nil then
						content[method_name] = nil
						break
					end
				end

				local context = DecoratorContext.new(
					decorator_name,
					decorator_args,
					nil,
					children_data,
					node,
					method_name,
					decorator_list,
					originalFunc,
					originalFunc,
					content
				)

				local wrappedChildren = originalFunc
				if children_data and #children_data > 0 then
					wrappedChildren = _wrap_children(originalFunc, children_data, context)
					context.WrappedFunction = wrappedChildren
					if wrappedChildren == nil then
						content[method_name] = nil
						break
					end
				end

				local wrapper = decorators[decorator_name]
				if wrapper then
					local result = wrapper(context, wrappedChildren, table.unpack(decorator_args))
					content[method_name] = result
				else
					content[method_name] = wrappedChildren
				end

				if decorator_name == "build" then
					if decorator_args[1] == true then
						build_targets[method_name] = true
					elseif method_name == "Build" and decorator_args[1] == false then
						build_targets.Build = nil
					end
				elseif decorator_name == "init" then
					if decorator_args[1] == true then
						init_targets[method_name] = true
					elseif method_name == "Init" and decorator_args[1] == false then
						init_targets.Init = nil
					end
				end

				if content[method_name] == nil then break end
			end
		end
	end

	node.InitTargets = init_targets
	_execute_targets(node, content, build_targets, "build")
end

local function _init_registry(): ()
	for _, node: Node in execution_queue do
		_execute_targets(node, node.Content, node.InitTargets, "ignition")
		node.InitTargets = nil
	end

	execution_queue = nil
end

--// Hook //--
-- Could be optimised in the future, but it's working fine. If you got any idea submit it in the github <3
local function _inject(scope: (...any?) -> (...any?), env: { [any]: any }): ()
	local proxy = {}

	env.script = instance_registry[env.script]

	setmetatable(proxy, {
		__index = function(_, key: any)
			return universe[key] or env[key]
		end,
		__metatable = true
	})

	setfenv(scope, proxy)
end

local function _hook_load(): ()
	_hook_load = nil

	setmetatable(_G, {
		__call = function(): (any?) -> (nil)
			local scope = debug.info(2, "f")
			local env = getfenv(scope)

			local source = env.script
			_scan(not source or not instance_registry[source])

			_inject(scope, env)

			return function(content: any?): nil
				local registry = instance_registry[source]

				local name_node = name_registry[registry.Name] or {}
				assert(name_node.Content == nil, `Attempt to register module '{registry.Name}', but a module with the same name already exists.`)

				registry.Content = content
				_build_content(registry, content)

				return nil
			end
		end,
	})
end

local function _hook_unload(): ()
	_hook_unload = nil
	setmetatable(_G, nil)
end

--// Public //--
return function(): ()
	_scan(ReplicatedStorage:GetAttribute("Loaded"..Context) or script.Parent ~= ReplicatedStorage)

	if client then
		script.Name = ""
		repeat task.wait() until ReplicatedStorage:GetAttribute("LoadedServer")
	end

	_register_roots()

	execution_queue = _order_by_priority(execution_queue, false)

	_hook_load()
	_load_registry()
	_hook_unload()

	_init_registry()

	ReplicatedStorage:SetAttribute("Loaded"..Context, true)
	ReplicatedStorage:GetAttributeChangedSignal("Loaded"..Context):Connect(function() _scan() end)

	if client then
		script:Destroy()
	end
end