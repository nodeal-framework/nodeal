--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local autoComplete = {}

-- Configuration --
local IntelliSenseId = "Nodeal.IntelliSense"

-- Services --
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ScriptEditorService = game:GetService("ScriptEditorService")

-- Types --
type CompletionItem = {
	name: string,
	type: "variable" | "function",

	prototype: string,
	methodes: { ('.' | ':')? },

	discovery: {
		type: "query" | "indexing",
		module: ModuleScript
	},

	completion: {
		label: string,
		kind: Enum.CompletionItemKind?,

		detail: string?,
		documentation: string?,
		codeSample: string?,

		learnMoreLink: string?,
		overloads: number?,

		tags: { [string]: boolean }?,
		preselect: boolean?
	},

	decorators: {
		{
			type: string,
			args: { any }
		}
	},

	metadata: { [string]: any },

	cache: { [string]: any },
	next: { any }
}

type AutocompleteRequestType = {
	position: {
		line: number,
		character: number,
	},
	textDocument: {
		document: ScriptDocument?,
		script: LuaSourceContainer?,
	},
}

type AutocompleteResponseType = {
	items: {
		{
			label: string,
			kind: Enum.CompletionItemKind?,
			tags: { Enum.CompletionItemTag }?,
			detail: string?,
			documentation: {
				value: string,
			}?,
			overloads: number?,
			learnMoreLink: string?,
			codeSample: string?,
			preselect: boolean?,
			textEdit: {
				newText: string,
				replace: {
					["start"]: { line: number, character: number },
					["end"]: { line: number, character: number },
				},
			}?,
		}
	},
}

-- Constants --
local Resources = script.Parent.Parent.Parent

local widget = script.Parent
local assets = widget.Assets

local plugin: plugin
local class

-- Modules --
local utils = require(Resources.Modules.Utils)

local PathParser = require(assets.PathParser)
local ParsingHandler = require(assets.ParsingHandler)

local ApiDump = require(assets.ApiDump)
local TypeParser = require(assets.TypeParser)
local TypeResolver = require(assets.TypeResolver)
local RegisterDecorator = require(assets.Analyzers.RegisterDecorator)
local ExtendCall = require(assets.Analyzers.ExtendCall)
local Snippets = {}
for _, snippetModule: ModuleScript? in assets.Snippets:GetChildren() do
	if not snippetModule:IsA("ModuleScript") then continue end
	local snippet = require(snippetModule)
	if snippet.prefix then
		Snippets[snippet.prefix] = Snippets[snippet.prefix] or {}
		table.insert(Snippets[snippet.prefix], snippet)
	end
end

local _CompletionItems = {}
for _, typeModule: ModuleScript? in assets.CompletionItems:GetChildren() do
	if not typeModule:IsA("ModuleScript") then continue end
	_CompletionItems[typeModule.Name] = require(typeModule)
end

local Decorators = {}
for _, module: ModuleScript? in assets.Decorators:GetChildren() do
	if not module:IsA("ModuleScript") then continue end
	Decorators[module.Name] = require(module)
end

-- Variables --
local toggeled = true
local dynamiqueTypes = {}
for index: string, value: any in _CompletionItems do
	dynamiqueTypes[index] = value
end

local dynamiqueDecorators = {}
for index: string, value: any in Decorators do
	dynamiqueDecorators[index] = value
end

local ModuleTypesCaches = {}
local ModuleServiceCaches = {}
local ModuleParsedCaches = {}
local DecoratorTypesCaches = {}

local requestContextCache: { [Instance]: { "client" | "server" } } = {}

local function getContextForRequest(instance: Instance?): { "client" | "server" }
	if not instance then return {} end
	local cached = requestContextCache[instance]
	if not cached then
		cached = utils.module.get_context(instance)
		requestContextCache[instance] = cached
	end
	return cached
end

local function ensureMethodArguments(item: any)
	if not item or type(item) ~= "table" then return end
	if item.arguments then return end
	local proto = item.prototype or item.detail or (item.completion and item.completion.detail)
	if proto and type(proto) == "string" then
		local ast = TypeParser.ParseSignature(proto)
		if ast and ast.arguments then
			item.arguments = ast.arguments
		end
	end
end

-- Lookups for Injected Parameters --
local function DecoratorLookup(name: string)
	if dynamiqueDecorators[name] then
		return dynamiqueDecorators[name]
	end
	if Decorators[name] then
		return Decorators[name]
	end
	for _, cache in DecoratorTypesCaches do
		if cache[name] then
			return cache[name]
		end
	end
	if RegisterDecorator.dynamicDecorators and RegisterDecorator.dynamicDecorators[name] then
		return RegisterDecorator.dynamicDecorators[name]
	end
	if ParsingHandler.DynamicDecorators then
		for _, mods in ParsingHandler.DynamicDecorators do
			if mods[name] then
				return mods[name]
			end
		end
	end
	return nil
end

autoComplete.ServicesCompletions = autoComplete.ServicesCompletions or {}
autoComplete.ModulesCompletions = autoComplete.ModulesCompletions or {}

-- [moduleName] = { [typeName]: parsedType } -- exported types, per indexed module
local dynamiqueExportedTypes = {}
TypeResolver.ExportedTypes = dynamiqueExportedTypes

local findExportedTypeOnDemand: ((typeName: string) -> any?)? = nil
local missedExportedTypes: { [string]: boolean } = {}

-- Functions --
local function StartsWith(str: string, prefix: string): boolean
	return string.sub(str, 1, #prefix) == prefix
end

local function hasRealInjectedParams(injected: { any }?): boolean
	if not injected or #injected == 0 then
		return false
	end
	for _, param in injected do
		local isGenericVar = (param.isVariadic or param.name == "..." or param.name == nil)
			and (param.type == "any" or param.type == "any?" or param.type == nil)
		if not isGenericVar then
			return true
		end
	end
	return false
end

local function ResolveImportedModuleName(val: string?): string?
	if not val or val == "" then return nil end

	-- Fast exit: only inspect expressions containing Get or require
	if string.find(val, "Get", 1, true) then
		local name = val:match("GetModule%s*%(%s*[\"']([%w_]+)[\"']")
			or val:match("GetService%s*%(%s*[\"']([%w_]+)[\"']")
		if name then return name end
	end

	if string.find(val, "require", 1, true) then
		local reqContent = val:match("require%s*(%b())")
		if reqContent then
			local inside = reqContent:sub(2, -2):match("^%s*(.-)%s*$") or ""
			-- 1. Quoted module name: require("ModuleName") or require(WaitForChild("ModuleName"))
			local strMatch = inside:match("[\"']([%w_]+)[\"']")
			if strMatch then return strMatch end
			-- 2. Dot-chained instance path: require(path.to.ModuleName)
			local tailIdent = inside:match("([%w_]+)%s*$")
			if tailIdent and tailIdent ~= "require" then
				return tailIdent
			end
		end
	end

	return nil
end

local function StartingWith(prefix: string, dict: {}): {}
	local results = {}

	local lowerPrefix = string.lower(prefix)

	for key, value in dict do
		if typeof(key) == "string" then
			local lowerKey = string.lower(key)
			if string.sub(lowerKey, 1, #lowerPrefix) == lowerPrefix then
				results[key] = value
			end
		end
	end

	return results
end

local function _generate_tags(completion: { [string]: any }): { Enum.CompletionItemTag? }
	completion.tags = completion.tags or {}

	if completion.kind == Enum.CompletionItemKind.Function or completion.kind == Enum.CompletionItemKind.Method then
		if typeof(completion.tags) == "table"
			and not table.find(completion.tags, Enum.CompletionItemTag.PutCursorInParens)
			and not completion.tags[Enum.CompletionItemTag.PutCursorInParens]
			and not completion.tags.PutCursorInParens then
			completion.tags[Enum.CompletionItemTag.PutCursorInParens] = true
		end
	end

	local tags = {}

	for index: any, value: any in completion.tags do
		if typeof(index) == "number" then
			local tag = value
			if typeof(tag) == "string" and Enum.CompletionItemTag[tag] then
				tag = Enum.CompletionItemTag[tag]
			end
			if tag then
				table.insert(tags, tag)
			end
		elseif value then
			local tag = (typeof(index) == "EnumItem" and index)
				or (typeof(index) == "string" and Enum.CompletionItemTag[index])
				or index
			if tag then
				table.insert(tags, tag)
			end
		end
	end

	return tags
end

local function _get_decorator_args(list: {any}, name: string): {any}
	for _, data in list do
		if type(data) == "table" and data[1] == name then
			return data[2] or {}
		end
	end
	return nil
end

local function SimplifyString(str: string): string
	local openParen = string.find(str, "%(")

	if openParen then
		return string.sub(str, 1, openParen - 1)
	else
		return str
	end
end

local function CountCallArgs(str: string): number
	local openParen = string.find(str, "(", 1, true)
	if not openParen then return 0 end

	local count = 0
	local inQuote = nil
	local depth = 0
	local len = #str

	for i = openParen + 1, len do
		local byte = string.byte(str, i)
		if inQuote then
			if byte == inQuote and string.byte(str, i - 1) ~= 92 then
				inQuote = nil
			end
		else
			if byte == 34 or byte == 39 then
				inQuote = byte
			elseif byte == 40 or byte == 123 or byte == 91 then
				depth += 1
			elseif byte == 41 or byte == 125 or byte == 93 then
				depth = math.max(0, depth - 1)
			elseif byte == 44 and depth == 0 then
				count += 1
			end
		end
	end

	return count
end

local function MergeAutocomplete(items: { [any]: any }, array: { [any]: any })
	if #array == 0 then return end

	local labelMap = {}
	for index, item in items do
		if item and item.label then
			labelMap[item.label] = index
		end
	end

	for _, value: any in array do
		if type(value.documentation) == "string" then
			value.documentation = { value = value.documentation }
		end

		local existingIndex = value.label and labelMap[value.label]
		if existingIndex then
			items[existingIndex] = value
		else
			table.insert(items, value)
			if value.label then
				labelMap[value.label] = #items
			end
		end
	end
end

local function ExtractArgs(input: string): {any}
	local args = {}

	local inside = string.match(input, "%b()")
	if not inside then
		return args
	end

	inside = string.sub(inside, 2, -2)

	for arg in string.gmatch(inside, "[^,]+") do
		arg = string.gsub(arg, "^%s*(.-)%s*$", "%1")

		if arg == "true" then
			table.insert(args, true)
		elseif arg == "false" then
			table.insert(args, false)
		elseif tonumber(arg) then
			table.insert(args, tonumber(arg))
		elseif string.match(arg, '^".*"$') or string.match(arg, "^'.*'$") then
			local str = string.sub(arg, 2, -2)
			table.insert(args, str)
		else
			table.insert(args, arg)
		end
	end

	return args
end

local function GetContent(value: any, ...: any): {}
	if typeof(value) == "table" then
		local modulesToLoad = nil
		for index: any, child: any in value do
			if typeof(child) == "Instance" and child:IsA("ModuleScript") then
				modulesToLoad = modulesToLoad or {}
				table.insert(modulesToLoad, { index = index, name = child.Name, module = child })
			end
		end
		if modulesToLoad then
			for _, item in modulesToLoad do
				value[item.index] = nil
				value[item.name] = require(item.module)
			end
		end

		return value
	elseif typeof(value) == "function" then
		return GetContent(value(...))
	elseif typeof(value) == "Instance" and value:IsA("ModuleScript") then
		return {
			[value.Name] = require(value)
		}
	else
		return {}
	end
end

local function formatParamType(param: any): string
	local t = param.type
	if type(t) == "table" then
		return (t.kind == "optional" and t.inner and (t.inner.name or t.inner.kind))
			or t.name or (t.path and table.concat(t.path, ".")) or "any"
	elseif type(t) == "string" then
		return t
	end
	return "any"
end

-- Method & Container Resolution for Injected Parameters --
local ApiClassMembersCache: { [string]: any } = {}

local function isCallable(item: any): boolean
	if type(item) ~= "table" then return false end
	if item.type == "function" then return true end
	if item.arguments or item.prototype then return true end
	local comp = item.completion
	if comp then
		if comp.kind == Enum.CompletionItemKind.Function or comp.kind == Enum.CompletionItemKind.Method then
			return true
		end
		if comp.detail and type(comp.detail) == "string" and string.find(comp.detail, "(", 1, true) then
			return true
		end
	end
	if item.kind == Enum.CompletionItemKind.Function or item.kind == Enum.CompletionItemKind.Method then
		return true
	end
	if item.detail and type(item.detail) == "string" and string.find(item.detail, "(", 1, true) then
		return true
	end
	return false
end

local function getMethodFromContainer(container: any, targetMethod: string): any
	if type(container) ~= "table" then return nil end

	-- 1. Direct member check on container table (O(1))
	local direct = container[targetMethod]
	if direct and isCallable(direct) then
		return direct
	end

	-- 2. Member inside .next (CompletionItem structure)
	local nextVal = container.next
	if type(nextVal) == "table" then
		-- Fast path: direct key in next table without calling GetContent (O(1))
		local member = nextVal[targetMethod]
		if member and isCallable(member) then
			return member
		end

		-- If not found directly, nextVal might contain ModuleScript instances (e.g. game.next)
		local resolved = GetContent(nextVal)
		if type(resolved) == "table" then
			local resolvedMember = resolved[targetMethod]
			if resolvedMember and isCallable(resolvedMember) then
				return resolvedMember
			end
		end
	elseif type(nextVal) == "function" then
		-- Lazy generator (e.g. ApiDump:warp)
		local members = container._cachedMembers
		if not members then
			members = GetContent(nextVal)
			if type(members) == "table" then
				container._cachedMembers = members
			end
		end
		if type(members) == "table" then
			local member = members[targetMethod]
			if member and isCallable(member) then
				return member
			end
		end
	end

	-- 3. Metatable fallback (__index) (O(1))
	local mt = getmetatable(container)
	if type(mt) == "table" and type(mt.__index) == "table" then
		local mtDirect = mt.__index[targetMethod]
		if mtDirect and isCallable(mtDirect) then
			return mtDirect
		end
	end

	return nil
end

local function lookupRoot(name: string, parser: any): any
	if not name or name == "" then return nil end

	-- Check services (O(1))
	if autoComplete.ServicesCompletions and autoComplete.ServicesCompletions[name] then
		return autoComplete.ServicesCompletions[name]
	end

	-- Check modules (O(1))
	if autoComplete.ModulesCompletions and autoComplete.ModulesCompletions[name] then
		return autoComplete.ModulesCompletions[name]
	end

	-- Check dynamic types / globals (O(1))
	if dynamiqueTypes and dynamiqueTypes[name] then
		return dynamiqueTypes[name]
	end

	-- Check built-in completion items (game, script, etc.) (O(1))
	if _CompletionItems and _CompletionItems[name] then
		return _CompletionItems[name]
	end

	-- Check parser's current module tables (O(1))
	if parser and parser.tables and parser.tables[name] then
		return parser.tables[name]
	end

	-- Check exported types
	if dynamiqueExportedTypes then
		for _, expTypes in dynamiqueExportedTypes do
			if expTypes and expTypes[name] then
				local astNode = expTypes[name]
				local resFields = TypeResolver.Resolve(astNode, parser or {})
				if resFields and next(resFields) then
					return { next = resFields }
				end
			end
		end
	end

	if findExportedTypeOnDemand then
		local astNode = findExportedTypeOnDemand(name)
		if astNode then
			local resFields = TypeResolver.Resolve(astNode, parser or {})
			if resFields and next(resFields) then
				return { next = resFields }
			end
		end
	end

	-- Check module cache
	if parser and parser.module and ModuleParsedCaches and ModuleParsedCaches[parser.module] and ModuleParsedCaches[parser.module][name] then
		return ModuleParsedCaches[parser.module][name]
	end

	-- Check Roblox ApiDump class with fast cache
	local cachedApi = ApiClassMembersCache[name]
	if cachedApi ~= nil then
		if cachedApi then return cachedApi end
	else
		local firstChar = name:sub(1, 1)
		-- Convention: Roblox classes start with uppercase
		if firstChar >= "A" and firstChar <= "Z" then
			local apiClass = ApiDump:GetAutoCompletion(name)
			if apiClass then
				local wrapper = { next = apiClass }
				ApiClassMembersCache[name] = wrapper
				return wrapper
			else
				ApiClassMembersCache[name] = false
			end
		end
	end

	-- Check if it's an instance root path (game, workspace, script)
	if (name == "game" or name == "workspace" or name == "Workspace" or name == "script") and TypeResolver and type(TypeResolver.ResolvePath) == "function" then
		local success, inst = pcall(function()
			return TypeResolver.ResolvePath(name, parser and parser.module)
		end)
		if success and inst then
			local classMembers = ApiDump:GetAutoCompletion(inst.ClassName)
			if classMembers then
				return { next = classMembers }
			end
		end
	end

	return nil
end

local function resolveCallerContainer(parser: any, callerExpr: string): any
	if not callerExpr or callerExpr == "" then return nil end

	local resolved = (parser and type(parser.Resolve) == "function" and parser:Resolve(callerExpr, 0, {})) or callerExpr
	if not resolved or resolved == "" then return nil end

	resolved = resolved:gsub(";%s*$", ""):match("^%s*(.-)%s*$") or ""
	if resolved == "" then return nil end

	-- Handle 'self'
	if resolved == "self" then
		if parser and parser.varMap and parser.varMap["self"] and parser.varMap["self"].val and parser.varMap["self"].val ~= "unknown" and parser.varMap["self"].val ~= "self" then
			resolved = parser.varMap["self"].val
		elseif parser and parser.module then
			resolved = parser.module.Name
		end
	end

	-- Fast path: single identifier without dots/colons/brackets
	if not resolved:find("[%.:%[%(%]]") then
		return lookupRoot(resolved, parser)
	end

	-- Transform bracket indexers: unknown["foo"] -> unknown.foo
	local parsedPath = resolved:gsub("%[%s*[\"'`]([^\"'`]*)[%s\"'`%]]*(%.?)", function(match, dot)
		return "." .. match .. (dot ~= "" and "." or "")
	end)

	local parts: { string } = {}
	for part: string in string.gmatch(parsedPath, "([^%.:]+)") do
		table.insert(parts, part)
	end

	if #parts == 0 then return nil end

	local rootPart = parts[1]
	local rootSimplified = SimplifyString(rootPart)
	local current = lookupRoot(rootSimplified, parser)
	if not current then return nil end

	local asArgs = StartsWith(rootPart, `{rootSimplified}(`)
	if asArgs and type(current) == "table" and current.next then
		local args = ExtractArgs(rootPart)
		current = GetContent(current.next, unpack(args))
	end

	for i = 2, #parts do
		if not current or type(current) ~= "table" then return nil end
		local part = parts[i]
		local simplified = SimplifyString(part)

		local members = current
		local nextVal = current.next
		if type(nextVal) == "table" then
			members = nextVal
		elseif type(nextVal) == "function" then
			members = current._cachedMembers
			if not members then
				members = GetContent(nextVal)
				if type(members) == "table" then
					current._cachedMembers = members
				end
			end
		end

		if type(members) ~= "table" then return nil end
		local child = members[simplified]
		if not child then return nil end

		current = child
		local partAsArgs = StartsWith(part, `{simplified}(`)
		if partAsArgs and type(current) == "table" and current.next then
			local args = ExtractArgs(part)
			current = GetContent(current.next, unpack(args))
		end
	end

	return current
end

local function MethodLookup(parser, callerExpr: string, callMethod: string, sep: string)
	if not callMethod or callMethod == "" then return nil end

	-- 1. Standalone function call without a caller expression
	if not callerExpr or callerExpr:match("^%s*$") then
		if parser and parser.tables and parser.tables[callMethod] and isCallable(parser.tables[callMethod]) then
			local found = parser.tables[callMethod]
			ensureMethodArguments(found)
			return found
		end
		if parser and parser.varMap and parser.varMap[callMethod] then
			local var = parser.varMap[callMethod]
			if type(var) == "table" and isCallable(var) then
				ensureMethodArguments(var)
				return var
			end
		end
		if dynamiqueTypes and dynamiqueTypes[callMethod] and isCallable(dynamiqueTypes[callMethod]) then
			local found = dynamiqueTypes[callMethod]
			ensureMethodArguments(found)
			return found
		end
		return nil
	end

	-- 2. Method/function call on a resolved container
	local container = resolveCallerContainer(parser, callerExpr)
	if container then
		local found = getMethodFromContainer(container, callMethod)
		if found then
			ensureMethodArguments(found)
			return found
		end
	end

	return nil
end

PathParser.SetLookups(DecoratorLookup, MethodLookup)

local tagSpecialMerge = {
	Deprecated = function(contexts: { string }, collected: { [string]: boolean? }): boolean
		local global = collected["global"]

		local index = table.find(contexts, "studio")
		if index then
			table.remove(contexts, index)
		end

		for _, context in contexts do
			local val = collected[context]

			if val == nil then
				val = global
			end

			if val ~= true then
				return false
			end
		end

		return true
	end
}

local specialMerge = {
	["hidden"] = tagSpecialMerge.Deprecated,
	["example"] = function(_, collected: { [string]: string? }): string
		collected["studio"] = nil

		local result = collected["global"] or ""
		collected["global"] = nil

		for context: string, value: string in collected do
			result = result.."\n--"..context.."--\n"..value
		end

		return result
	end,
	["overloads"] = function(_, collected: { [string]: number? }): number?
		if collected["client"] or collected["server"] then
			return (collected["client"] or 0) + (collected["server"] or 0)
		else
			return collected["global"]
		end
	end,
	["tags"] = function(contexts: { string }, collected: { [string]: { [string]: any }? }): { [string]: any }
		local result = {}

		local allTags = {}
		for _, tagsInContext in collected do
			for tagName, _ in tagsInContext do
				allTags[tagName] = true
			end
		end

		for tagName, _ in allTags do
			local tagCollected = {}
			for ctxName, tagsInContext in collected do
				if tagsInContext then
					tagCollected[ctxName] = tagsInContext[tagName]
				end
			end

			if tagSpecialMerge[tagName] then
				result[tagName] = tagSpecialMerge[tagName]({unpack(contexts)}, tagCollected)
			else
				local val = tagCollected["global"]
				for _, ctx in contexts do
					if ctx == "studio" then continue end
					if tagCollected[ctx] ~= nil then
						val = tagCollected[ctx]
					end
				end
				result[tagName] = val
			end
		end

		return result
	end,
}

local function IsTypeContext(sourceLines: { string }, line: number, character: number): boolean
	local prefix = ""
	local startLine = math.max(1, line - 9)
	for i = startLine, line do
		local l = sourceLines[i] or ""
		if i == line then l = string.sub(l, 1, character - 1) end
		l = string.gsub(l, "%-%-[^\n]*", "") 
		prefix ..= l .. "\n"
	end

	local len = #prefix
	local depth = 0
	local i = len

	while i > 0 do
		local c = prefix:sub(i, i)
		if c:match("%s") then
			i -= 1
		elseif c == ")" or c == "}" or c == ">" or c == "]" then
			depth += 1
			i -= 1
		elseif c == "(" or c == "{" or c == "<" or c == "[" then
			if depth > 0 then
				depth -= 1
				i -= 1
			else
				if c == "<" then return true end
				if c == "(" then
					local beforeParen = prefix:sub(1, i-1)
					if beforeParen:match("typeof%s*$") then return false end
				end
				i -= 1
			end
		elseif depth > 0 then
			if c == '"' or c == "'" or c == "`" then
				local quote = c
				i -= 1
				while i > 0 and prefix:sub(i, i) ~= quote do i -= 1 end
				i -= 1
			else
				i -= 1
			end
		else
			if c:match("[%w_%.%']") or c == '"' then
				if c == '"' or c == "'" or c == "`" then
					local quote = c
					i -= 1
					while i > 0 and prefix:sub(i, i) ~= quote do i -= 1 end
					i -= 1
				else
					i -= 1
				end
			elseif c == ":" then
				local trimmed = prefix:sub(1, i-1):match("^(.-)%s*$") or ""
				local kw = trimmed:match("([lc]%w+)%s+[%w_]+$")
				if kw == "local" or kw == "const" then return true end
				if trimmed:match("[%{%(%,<]%s*[%w_]+$") then return true end
				if trimmed:sub(-1) == ")" then
					local d = 0
					local j = #trimmed
					while j > 0 do
						local char = trimmed:sub(j, j)
						if char == ")" then d += 1
						elseif char == "(" then
							d -= 1
							if d == 0 then
								local beforeParen = trimmed:sub(1, j-1):match("^(.-)%s*$") or ""
								if beforeParen:match("function%s*[%w_%.%:]*$") or beforeParen:match("function$") then
									return true
								end
								break
							end
						end
						j -= 1
					end
				elseif trimmed:sub(-1) == "]" then
					local d = 0
					local j = #trimmed
					while j > 0 do
						local char = trimmed:sub(j, j)
						if char == "]" then d += 1
						elseif char == "[" then
							d -= 1
							if d == 0 then
								local beforeBracket = trimmed:sub(1, j-1):match("^(.-)%s*$") or ""
								if beforeBracket:match("[%{%,]$") then
									return true
								end
								break
							end
						end
						j -= 1
					end
				end
				return false
			elseif c == "-" and prefix:sub(i-1, i-1) == "-" then
				i -= 2
			elseif c == ">" and prefix:sub(i-1, i-1) == "-" then
				return true
			elseif c == "=" then
				local beforeEq = prefix:sub(1, i-1)
				if beforeEq:match("type%s+[%w_]+%s*$") or beforeEq:match("export%s+type%s+[%w_]+%s*$") then return true end
				return false
			elseif c == "|" or c == "&" or c == "?" then
				return true
			elseif c == "," then
				return false
			else
				return false
			end
		end
	end
	return false
end

--// Path Resolver //--
local function _AutocompleteCallback(request: AutocompleteRequestType, response: AutocompleteResponseType): AutocompleteResponseType
	local origin = request.textDocument.script
	if not origin or not origin:IsA("LuaSourceContainer") then return response end

	table.clear(requestContextCache)

	local line = request.position.line
	local character = request.position.character

	local source = ScriptEditorService:GetEditorSource(origin)
	local cleanSource = source
	if string.find(source, "\r", 1, true) then
		cleanSource = source:gsub("\r\n", "\n"):gsub("\r", "\n")
	end
	local sourceLines = string.split(cleanSource, "\n")
	local parsedPath, is_comment, parser = PathParser(cleanSource, line, character, sourceLines)

	-- print(parsedPath, is_comment)

	if is_comment then
		local currentLineStr = sourceLines[line] and string.sub(sourceLines[line], 1, character) or ""

		local decPrefix, spaceAndArgs = string.match(currentLineStr, "@([%w_]+)(%s+.*)$")
		if decPrefix and spaceAndArgs then
			local parts = string.split(spaceAndArgs, " ")
			local currentArgIndex = 0
			local currentTyping = ""

			for i, part in parts do
				if i == 1 then continue end 

				if part ~= "" or i == #parts then
					currentArgIndex += 1
					if i == #parts then
						currentTyping = part
					end
				end
			end

			local decorator = dynamiqueDecorators[decPrefix]

			if decorator then
				local completion = decorator.completion or {}
				local isValidContext = true

				if type(completion.context) == "function" then
					local success, isValid = pcall(completion.context, source, line)
					if not success or not isValid then isValidContext = false end
				end

				if isValidContext and completion.args then
					local possibilities = completion.args.variadic or completion.args[currentArgIndex]

					if possibilities then
						local items = response.items
						for _, poss in possibilities do
							if StartsWith(poss, currentTyping) then
								table.insert(items, {
									label = poss,
									kind = Enum.CompletionItemKind.EnumMember,
									textEdit = {
										newText = poss,
										replace = {
											["start"] = { line = line, character = character - string.len(currentTyping) },
											["end"] = { line = line, character = character },
										},
									}
								})
							end
						end
					end
				end
				return response
			end
		end

		if string.sub(parsedPath, 1, 1) ~= "@" then return response end

		local items = response.items

		for name: string, decorator: any in dynamiqueDecorators do
			local completion = decorator.completion or {}

			if type(completion.context) == "function" then
				local success, isValid = pcall(completion.context, source, line)
				if not success or not isValid then continue end
			end

			table.insert(items, {
				label = "@"..name,
				kind = completion.kind or Enum.CompletionItemKind.Event,
				detail = completion.detail,
				documentation = completion.documentation and { value = completion.documentation },
				overloads = completion.overloads,
				preselect = completion.preselect,

				textEdit = {
					newText = name,
					replace = {
						["start"] = { line = line, character = character - string.len(parsedPath) + 1 },
						["end"] = { line = line, character = character },
					},
				}
			})
		end

		return response
	end

	-- Parameter autocompletion inside `function(|)`
	do
		local currentLine = sourceLines[line] or ""
		local currentLineStr = currentLine:sub(1, math.max(0, character - 1))
		local insideParams = currentLineStr:match("function%s*[%w_%.:]*%s*%(([^%)]*)$")
		local funcLine = line
		if not insideParams then
			-- Multi-line function parameter list check
			local combined = currentLineStr
			for scanBack = line - 1, math.max(1, line - 10), -1 do
				local prevL = sourceLines[scanBack] or ""
				combined = prevL .. "\n" .. combined
				local m = combined:match("function%s*[%w_%.:]*%s*%(([^%)]*)$")
				if m then
					insideParams = m
					funcLine = scanBack
					break
				end
				if prevL:find("%)") or prevL:find("end") then
					break
				end
			end
		end

		if insideParams then
			local injected = nil
			-- Check for decorator above (supporting --[=[ ... ]=] docblocks and single line comments)
			local inMultiComment = nil
			for scanLine = funcLine - 1, math.max(1, funcLine - 25), -1 do
				local rawLine = sourceLines[scanLine] or ""
				local trimmed = rawLine:match("^%s*(.-)%s*$")
				if trimmed == "" and not inMultiComment then
					continue
				end

				if not inMultiComment then
					local closeEq = rawLine:match("%](=*)%]")
					if closeEq then
						inMultiComment = closeEq
					end
				end

				if inMultiComment then
					for decName in rawLine:gmatch("@([%w_]+)") do
						local dec = DecoratorLookup(decName)
						if dec and dec.injectedParameters and hasRealInjectedParams(dec.injectedParameters) then
							injected = dec.injectedParameters
							break
						end
					end
					if injected then break end

					local openMatch = rawLine:match("%-%-%[(=*)%[")
					if openMatch and openMatch == inMultiComment then
						inMultiComment = nil
					end
				else
					if rawLine:match("^%s*%-%-") then
						for decName in rawLine:gmatch("@([%w_]+)") do
							local dec = DecoratorLookup(decName)
							if dec and dec.injectedParameters and hasRealInjectedParams(dec.injectedParameters) then
								injected = dec.injectedParameters
								break
							end
						end
						if injected then break end
					else
						break
					end
				end
			end

			-- Check for enclosing call if no decorator
			if not injected then
				local callerExpr, callSep, callMethod = nil, nil, nil
				local c, sep, method = currentLineStr:match("^(.-)([:%.])([%w_]+)%s*%([^%)]*function")
				if method and sep then
					callerExpr = c:match("([%w_%.:]+)%s*$") or c:match("^%s*(.-)%s*$")
					callSep = sep
					callMethod = method
				else
					local standalone = currentLineStr:match("([%w_]+)%s*%([^%)]*function")
					if standalone and standalone ~= "function" then
						callMethod = standalone
						callSep = ""
						callerExpr = ""
					end
				end

				if not callMethod then
					for scanLine = funcLine - 1, math.max(1, funcLine - 5), -1 do
						local pLine = sourceLines[scanLine] or ""
						local pCaller, pSep, pMethod = pLine:match("^(.-)([:%.])([%w_]+)%s*%([^%)]*$")
						if pMethod and pSep then
							callerExpr = pCaller:match("([%w_%.:]+)%s*$") or pCaller:match("^%s*(.-)%s*$")
							callSep = pSep
							callMethod = pMethod
							break
						else
							local standalone = pLine:match("([%w_]+)%s*%([^%)]*$")
							if standalone and standalone ~= "function" then
								callMethod = standalone
								callSep = ""
								callerExpr = ""
								break
							end
						end
					end
				end

				if callMethod and MethodLookup then
					local methodItem = MethodLookup(parser, callerExpr or "", callMethod, callSep or "")
					if methodItem and methodItem.arguments then
						for _, arg in methodItem.arguments do
							if arg.type and arg.type.kind == "function" and arg.type.arguments then
								injected = arg.type.arguments
								break
							end
						end
					end
				end
			end

			if injected and hasRealInjectedParams(injected) then
				local currentTyping = insideParams:match("([%w_%.]+)$") or ""

				-- Determine current parameter index by counting top-level commas (0 allocations)
				local commaCount = 0
				local parenDepth = 0
				for k = 1, #insideParams do
					local b = string.byte(insideParams, k)
					if b == 40 or b == 60 or b == 123 then -- ( or < or {
						parenDepth += 1
					elseif b == 41 or b == 62 or b == 125 then -- ) or > or }
						if parenDepth > 0 then parenDepth -= 1 end
					elseif b == 44 and parenDepth == 0 then -- ,
						commaCount += 1
					end
				end

				local argIndex = commaCount + 1
				local totalInjected = #injected

				if argIndex <= totalInjected then
					local remainingCount = totalInjected - argIndex + 1

					-- 1. Bulk completion (when more than 1 parameter remains)
					if remainingCount > 1 then
						local bulkNames = table.create(remainingCount)
						local bulkSigParts = table.create(remainingCount)

						for idx = argIndex, totalInjected do
							local p = injected[idx]
							local isVar = p.isVariadic or p.name == "..."
							if isVar then
								local varType = p.type
								if varType and varType ~= "any" and type(varType) == "string" then
									table.insert(bulkSigParts, varType:find("^%.%.%.") and varType or `...{varType}`)
								else
									table.insert(bulkSigParts, "...any")
								end
								table.insert(bulkNames, "...")
							else
								local pType = formatParamType(p)
								local pName = p.name
								table.insert(bulkNames, pName)
								if pType and pType ~= "any" then
									table.insert(bulkSigParts, `{pName}: {pType}`)
								else
									table.insert(bulkSigParts, pName)
								end
							end
						end

						local bulkLabel = table.concat(bulkNames, ", ")
						local bulkDetail = `({table.concat(bulkSigParts, ", ")})`

						local firstParam = injected[argIndex]
						local firstName = (firstParam.isVariadic or firstParam.name == "...") and "..." or firstParam.name
						local bulkMatches = currentTyping == ""
							or StartsWith(firstName:lower(), currentTyping:lower())
							or StartsWith(bulkLabel:lower(), currentTyping:lower())

						if bulkMatches then
							table.insert(response.items, {
								label = bulkLabel,
								kind = Enum.CompletionItemKind.Snippet,
								detail = bulkDetail,
								preselect = true,
								textEdit = {
									newText = bulkLabel,
									replace = {
										["start"] = { line = line, character = character - #currentTyping },
										["end"] = { line = line, character = character },
									},
								},
							})
						end
					end

					-- 2. Individual parameter completion strictly for the CURRENT slot only
					local currentParam = injected[argIndex]
					local isVar = currentParam.isVariadic or currentParam.name == "..."
					if isVar then
						local varMatches = currentTyping == ""
							or StartsWith("...", currentTyping)
							or StartsWith(currentTyping, ".")
						if varMatches then
							local varType = currentParam.type
							local detailStr = (varType and type(varType) == "string")
								and (varType:find("^%.%.%.") and varType or `...{varType}`)
								or "...any"
							table.insert(response.items, {
								label = "...",
								kind = Enum.CompletionItemKind.Variable,
								detail = detailStr,
								preselect = (remainingCount == 1 and currentTyping ~= ""),
								textEdit = {
									newText = "...",
									replace = {
										["start"] = { line = line, character = character - #currentTyping },
										["end"] = { line = line, character = character },
									},
								},
							})
						end
					else
						local pType = formatParamType(currentParam)
						local pName = currentParam.name
						local matches = currentTyping == ""
							or StartsWith(pName:lower(), currentTyping:lower())

						if matches then
							local detailStr = (pType and pType ~= "any") and `{pName}: {pType}` or pName
							table.insert(response.items, {
								label = pName,
								kind = Enum.CompletionItemKind.Variable,
								detail = detailStr,
								preselect = (remainingCount == 1),
								textEdit = {
									newText = pName,
									replace = {
										["start"] = { line = line, character = character - #currentTyping },
										["end"] = { line = line, character = character },
									},
								},
							})
						end
					end
				end
				if #response.items > 0 then
					return response
				end
			end
		end
	end

	--// Snippets (:ServiceName, $ModuleName, !--[=[, etc.) //--
	local linePrefix = (sourceLines[line] or ""):sub(1, character - 1)
	local snippetPrefix = linePrefix:match("^%s*([:%$!])")

	if snippetPrefix and Snippets[snippetPrefix] and not is_comment then
		local startChar = linePrefix:find("[:%$!][^:%$!]*$") or (character - 1)
		local replaceRange = {
			start = { line = line, character = startChar },
			["end"] = { line = line, character = character },
		}

		for _, snippet in Snippets[snippetPrefix] do
			local items = snippet.provide(origin, autoComplete)
			if items then
				for _, item in items do
					item.preselect = true
					item.textEdit = {
						newText = item.newText or item.detail or item.label,
						replace = replaceRange,
					}
					table.insert(response.items, item)
				end
			end
		end

		if #response.items > 0 then
			return response
		end
	end

	-- Comparison against a string-literal union: `if State == "` offers the union members.
	do
		local currentLine = (sourceLines[line] or ""):sub(1, character - 1)
		local operand, _, typed = currentLine:match("([%w_]+)%s*[=~]=%s*([\"'])([^\"']*)$")


		local varData = operand and parser and parser.varMap and parser.varMap[operand]
		local annotation = varData and varData.typeAnnotation
		local node

		if annotation then
			local holder, typeName = annotation:match("^([%w_]+)%.([%w_]+)$")

			if holder then
				local holderData = parser.varMap[holder]
				local source_call = holderData and holderData.val and ResolveImportedModuleName(holderData.val)
				local exported = dynamiqueExportedTypes[source_call or holder]

				node = exported and exported[typeName]
			else
				local aliasData = parser.varMap[annotation]
				node = (aliasData and aliasData.isType and aliasData.val) and TypeParser.Parse(aliasData.val) or nil
			end
		end

		if node and node.kind == "union" then
			for _, member: { [string]: any } in node.types do
				if member.kind ~= "literal" or member.literalType ~= "string" then continue end

				table.insert(response.items, {
					label = member.value,
					kind = Enum.CompletionItemKind.EnumMember,
					detail = annotation,
					textEdit = {
						newText = member.value,
						replace = {
							["start"] = { line = line, character = character - string.len(typed) },
							["end"] = { line = line, character = character },
						},
					}
				})
			end

			return response
		end
	end

	if IsTypeContext(sourceLines, line, character) then
		-- Qualified type path (`RoundConstants.`): only that module's exported types apply,
		-- so never fall through to the flat list below.
		local qualifier = parsedPath and parsedPath:match("([%w_]+)%s*%.%s*[%w_]*$")

		if qualifier then
			local extended = TypeResolver.ExtendRegistry and TypeResolver.ExtendRegistry[qualifier]
			if extended then
				for subTypeName: string, subTypeData in extended do
					local detail = (type(subTypeData) == "table" and subTypeData.detail) or `type {qualifier}.{subTypeName}`
					local doc = (type(subTypeData) == "table" and subTypeData.documentation) or nil
					table.insert(response.items, {
						label = subTypeName,
						kind = Enum.CompletionItemKind.Struct,
						detail = detail,
						documentation = doc and { value = doc } or nil,
					})
				end
			end

			local varData = parser and parser.varMap and parser.varMap[qualifier]
			local source_call = varData and varData.val and ResolveImportedModuleName(varData.val)

			for typeName: string in dynamiqueExportedTypes[source_call or qualifier] or {} do
				table.insert(response.items, {
					label = typeName,
					kind = Enum.CompletionItemKind.Struct,
					detail = `type {source_call or qualifier}.{typeName}`
				})
			end

			return response
		end

		local primitives = {"string", "number", "boolean", "any", "unknown", "thread", "buffer", "typeof", "never"}
		for _, p in primitives do
			table.insert(response.items, {
				label = p,
				kind = Enum.CompletionItemKind.Keyword,
				detail = p
			})
		end

		for typeName, handler in TypeResolver.Registry do
			if handler.completion then
				local comp = handler.completion
				table.insert(response.items, {
					label = typeName,
					kind = comp.kind or Enum.CompletionItemKind.Class,
					detail = comp.detail,
					documentation = comp.documentation and { value = comp.documentation } or nil
				})
			end
		end

		for typeName, _ in dynamiqueTypes do
			if type(typeName) == "string" and not typeName:match("^__") then
				table.insert(response.items, {
					label = typeName,
					kind = Enum.CompletionItemKind.Class,
					detail = typeName
				})
			end
		end

		if parser and parser.varMap then
			for varName, varData in parser.varMap do
				if not varName:match("^__") and not varName:match("%.") then
					table.insert(response.items, {
						label = varName,
						kind = varData.isType and Enum.CompletionItemKind.Struct or Enum.CompletionItemKind.Class,
						detail = varData.isType and ("type " .. varName) or varName
					})
				end
			end
		end

		return response
	end

	-- Transform string bracket indexers into dot notation for completion
	-- e.g. unknown["foo"].Name -> unknown.foo.Name
	parsedPath = parsedPath:gsub("%[%s*[\"'`]([^\"'`]*)[%s\"'`%]]*(%.?)", function(match, dot)
		return "." .. match .. (dot ~= "" and "." or "")
	end)

	local parts = {}
	for part: string, methode: string in string.gmatch(parsedPath, "([^%.:]+)([%.:]?)") do
		table.insert(parts, { part = part, methode = methode })
	end

	if #parsedPath > 0 then
		local methode

		if parsedPath:sub(-1) == "." then
			methode = "."
		elseif parsedPath:sub(-1) == ":" then
			methode = ":"
		end

		if methode then
			table.insert(parts, { part = "", methode = methode })
		end
	end

	local module_context = getContextForRequest(origin)

	local items = {}

	local innerPath = nil
	do
		local depth = 0
		for k = #parsedPath, 1, -1 do
			local c = parsedPath:sub(k, k)
			if c == ")" or c == "}" or c == "]" then
				depth += 1
			elseif c == "(" or c == "{" or c == "[" then
				if depth > 0 then
					depth -= 1
				else
					local inner = parsedPath:sub(k + 1):gsub("^[{%[%s]*", ""):match("^%s*(.-)%s*$") or ""
					if inner ~= "" and inner:find("[%.:%w_]") and inner:find("[%.:]")
						and not inner:match('^["\']') then
						innerPath = inner
					end
					break
				end
			end
		end
	end

	local object = dynamiqueTypes
	for index: number, data: { [string]: string } in parts do
		local part = data.part
		local methode = parts[index - 1] and parts[index - 1].methode or ""

		local simplified = SimplifyString(part)

		local hasChild: boolean, child: any = pcall(function()
			return object[simplified]
		end)

		if not (hasChild and child) then
			if index == 1 then
				local varData = parser and parser.varMap and parser.varMap[simplified]
				if varData and (varData.members or (type(varData.typeAnnotation) == "table" and varData.typeAnnotation.members)) then
					local mems = varData.members or varData.typeAnnotation.members
					child = { next = mems }
					hasChild = true
				elseif autoComplete.ServicesCompletions and autoComplete.ServicesCompletions[simplified] then
					child = autoComplete.ServicesCompletions[simplified]
					hasChild = true
				elseif autoComplete.ModulesCompletions and autoComplete.ModulesCompletions[simplified] then
					child = autoComplete.ModulesCompletions[simplified]
					hasChild = true
				else
					for _, expTypes in dynamiqueExportedTypes do
						if expTypes and expTypes[simplified] then
							local astNode = expTypes[simplified]
							local resFields = TypeResolver.Resolve(astNode, parser or {})
							if resFields and next(resFields) then
								child = { next = resFields }
								hasChild = true
								break
							end
						end
					end
					if not hasChild and findExportedTypeOnDemand then
						local astNode = findExportedTypeOnDemand(simplified)
						if astNode then
							local resFields = TypeResolver.Resolve(astNode, parser or {})
							if resFields and next(resFields) then
								child = { next = resFields }
								hasChild = true
							end
						end
					end
				end
			elseif typeof(object) == "table" and object.name then
				local astNode = nil
				if dynamiqueExportedTypes[object.name] and dynamiqueExportedTypes[object.name][simplified] then
					astNode = dynamiqueExportedTypes[object.name][simplified]
				elseif findExportedTypeOnDemand then
					astNode = findExportedTypeOnDemand(simplified)
				end
				if astNode then
					local resFields = TypeResolver.Resolve(astNode, parser or {})
					if resFields and next(resFields) then
						child = { next = resFields }
						hasChild = true
					end
				end
			end
		end

		local asArgs = StartsWith(part, `{simplified}(`)

		if not (index == #parts and asArgs) and (hasChild and child) then
			object = child

			if typeof(object) == "table" and object.next then
				local args = ExtractArgs(part)

				object = GetContent(object.next, unpack(args))
			end
		elseif not asArgs then
			if index ~= #parts then break end
			local possible = object

			-- print(possible)

			for Id: string, CompletionItem: CompletionItem in possible do
				if typeof(CompletionItem) ~= "table" then continue end

				local completion = CompletionItem.completion
				local metadata = CompletionItem.metadata

				if not completion then continue end

				completion.label = completion.label or Id
				if string.sub(completion.label, 1, 2) == "__" then continue end

				local target_context = CompletionItem.discovery and CompletionItem.discovery.module and getContextForRequest(CompletionItem.discovery.module)
				if target_context then
					local has_overlap = false
					for _, o_ctx in module_context do
						if table.find(target_context, o_ctx) then
							has_overlap = true
							break
						end
					end

					if not has_overlap and not utils.module.has_universal_access(module_context, completion) then
						continue
					end
				end

				if metadata then
					-- TODO: fix for new decorator structure, need to flat by context
					local collected_merges = {}
					local context_visible = false

					for key: number | string, value: any in metadata do
						if type(key) == "string" then
							collected_merges[key] = {global = value}
						end
					end

					for _, contextName: string in module_context do
						local overrideData = _get_decorator_args(metadata, contextName)

						if not overrideData or overrideData[1] ~= false then
							context_visible = true
						end
						if not overrideData or type(overrideData[1]) == "boolean" then continue end -- Skip for disabled context and unspecified contexts.
						-- TODO add @client true logic that disable server execution or other way
						for key: number | string, content: any in overrideData do
							if type(key) == "string" then
								collected_merges[key] = collected_merges[key] or {}
								collected_merges[key][contextName] = content
							end
						end
					end

					if not context_visible then continue end -- Skip for not visible in context.

					for key: string, packed_contexts: { [string]: any } in collected_merges do
						if not specialMerge[key] then continue end
						completion[key] = specialMerge[key](module_context, packed_contexts)
					end
				end

				if completion.default then
					local default = false

					for _, content in response.items do
						if content.label ~= completion.label then continue end

						default = true
						break
					end

					if default then continue end
				end

				if methode ~= "" and (CompletionItem.methodes and not table.find(CompletionItem.methodes, methode)) then continue end -- <- issues
				if completion.hidden then continue end

				table.insert(items, {
					label = completion.label,
					kind = completion.kind,
					detail = completion.detail,
					documentation = (type(completion.documentation) == "table" and completion.documentation)
						or (completion.documentation and { value = completion.documentation }) or nil,
					overloads = completion.overloads,
					learnMoreLink = completion.learnMoreLink,
					tags = _generate_tags(completion),
					codeSample = completion.example and string.match(completion.example, "^%s*(.-)%s*$") or nil,
					preselect = completion.preselect
				})
			end
		elseif asArgs then
			local datas = object[simplified]

			local count = CountCallArgs(part)
			if datas and datas.args and datas.args[count + 1] then
				local possible = datas.args[count + 1]
				local args = GetContent(possible, origin)

				local processedArgs = {}
				local argTyping = part:match(",%s*([%w_]*)$") or part:match("%(%s*([%w_]*)$") or ""

				for idx, argItem in args do
					if type(argItem) == "table" then
						local cloned = table.clone(argItem)
						if type(cloned.documentation) == "string" then
							cloned.documentation = { value = cloned.documentation }
						end
						if cloned.insertText then
							cloned.textEdit = {
								newText = cloned.insertText,
								replace = {
									["start"] = { line = line, character = character - #argTyping },
									["end"] = { line = line, character = character },
								},
							}
						end
						processedArgs[idx] = cloned
					else
						processedArgs[idx] = argItem
					end
				end

				-- Don't overwrite if the user is typing a code expression inside the arg
				if args.overwrite and not innerPath then
					response.items = processedArgs
					response.overwrite = nil
				else
					MergeAutocomplete(response.items, processedArgs)
				end
			end
		end
	end

	MergeAutocomplete(response.items, items)

	if innerPath then
		local subParts = {}
		for subPart, subMethode in string.gmatch(innerPath, "([^%.:]+)([%.:]?)") do
			table.insert(subParts, { part = subPart, methode = subMethode })
		end
		if innerPath:sub(-1) == "." then
			table.insert(subParts, { part = "", methode = "." })
		elseif innerPath:sub(-1) == ":" then
			table.insert(subParts, { part = "", methode = ":" })
		end

		local subObject = dynamiqueTypes
		local subItems = {}

		for subIndex, subData in subParts do
			local subPart = subData.part
			local subMethode = subParts[subIndex - 1] and subParts[subIndex - 1].methode or ""

			local subSimplified = SimplifyString(subPart)
			local subHasChild, subChild = pcall(function() return subObject[subSimplified] end)
			if (not subHasChild or not subChild) and subIndex == 1 then
				local varData = parser and parser.varMap and parser.varMap[subSimplified]
				if varData and (varData.members or (type(varData.typeAnnotation) == "table" and varData.typeAnnotation.members)) then
					subChild = { next = varData.members or varData.typeAnnotation.members }
					subHasChild = true
				end
			end
			local subAsArgs = StartsWith(subPart, `{subSimplified}(`)

			if not (subIndex == #subParts and subAsArgs) and (subHasChild and subChild) then
				subObject = subChild
				if typeof(subObject) == "table" and subObject.next then
					local subArgs = ExtractArgs(subPart)
					subObject = GetContent(subObject.next, unpack(subArgs))
				end
			elseif not subAsArgs then
				if subIndex ~= #subParts then break end
				for subId, subCompletionItem in subObject do
					if typeof(subCompletionItem) ~= "table" then continue end
					local subCompletion = subCompletionItem.completion
					if not subCompletion then continue end
					subCompletion.label = subCompletion.label or subId
					if string.sub(subCompletion.label, 1, 2) == "__" then continue end
					if subMethode ~= "" and (subCompletionItem.methodes and not table.find(subCompletionItem.methodes, subMethode)) then continue end
					if subCompletion.hidden then continue end
					table.insert(subItems, {
						label = subCompletion.label,
						kind = subCompletion.kind,
						detail = subCompletion.detail,
						documentation = (type(subCompletion.documentation) == "table" and subCompletion.documentation)
							or (subCompletion.documentation and { value = subCompletion.documentation }) or nil,
						overloads = subCompletion.overloads,
						learnMoreLink = subCompletion.learnMoreLink,
						tags = _generate_tags(subCompletion),
						codeSample = subCompletion.example and string.match(subCompletion.example, "^%s*(.-)%s*$") or nil,
						preselect = subCompletion.preselect
					})
				end
			end
		end

		MergeAutocomplete(response.items, subItems)
	end

	return response
end

local function AutocompleteCallback(request: AutocompleteRequestType, response: AutocompleteResponseType): AutocompleteResponseType
	local res = _AutocompleteCallback(request, response)
	if res and res.items then
		for _, item in res.items do
			if type(item.documentation) == "string" then
				item.documentation = { value = item.documentation }
			end
		end
	end
	return res
end

---------------------------------------------------------------------------------------

--// Indexer //--
local indexing_toggled = true

local RootConnectors = {}

autoComplete.ServicesCompletions = {}
autoComplete.ModulesCompletions = {}

ModuleTypesCaches = {}
ModuleServiceCaches = {}
local ModuleModulesCaches = {}
DecoratorTypesCaches = {}
local MissingDecoratorsMap = {}
local IndexThreads = {}
local Index
local RequestIndex
local EnqueueIndex: (module: ModuleScript, isPriority: boolean?) -> ()
local IndexQueue = {}
local QueueSet = {}

-- Les modules dont on a deja propage le changement pendant ce vidage de file.
local CascadedThisDrain = {}
local ForceCascadeNext = {}
local queueActive = false
local queueIndex = 1
local debounceThread = nil

local RebuildDynamiqueTypes
local RebuildDynamiqueServices
local RebuildDynamiqueModules
local RebuildDynamiqueDecorators

local function ResolveWaitingForDecorators(decoratorNames: { [string]: any })
	for decoratorName in decoratorNames do
		local waitingModules = MissingDecoratorsMap[decoratorName]
		if waitingModules then
			for waitingModule in waitingModules do
				CascadedThisDrain[waitingModule] = nil
				ForceCascadeNext[waitingModule] = true
				EnqueueIndex(waitingModule, true)
			end
			MissingDecoratorsMap[decoratorName] = nil
		end
	end
end

ParsingHandler.OnDecoratorsDiscovered = function(_moduleScript: ModuleScript, decorators: { [string]: any })
	ResolveWaitingForDecorators(decorators)
end

EnqueueIndex = function(module: ModuleScript, isPriority: boolean?)
	if not indexing_toggled then return end

	if QueueSet[module] then
		if isPriority and queueActive then
			local existingIdx = table.find(IndexQueue, module, queueIndex)
			if existingIdx and existingIdx > queueIndex then
				table.remove(IndexQueue, existingIdx)
				table.insert(IndexQueue, queueIndex, module)
			end
		end
		return
	end

	if isPriority and queueActive then
		table.insert(IndexQueue, queueIndex, module)
	else
		table.insert(IndexQueue, module)
	end
	QueueSet[module] = true

	if not queueActive then
		queueActive = true

		task.spawn(function()
			local ok, err = pcall(function()
				local lastYield = os.clock()

				while queueIndex <= #IndexQueue do
					if not indexing_toggled then break end

					local nextModule = IndexQueue[queueIndex]
					queueIndex += 1
					QueueSet[nextModule] = nil

					if os.clock() - lastYield > 0.005 then
						task.wait()
						lastYield = os.clock()
					end

					if nextModule.Parent then
						local changed = Index(nextModule)
						local forceCascade = ForceCascadeNext[nextModule]
						ForceCascadeNext[nextModule] = nil
						-- Propagate to dependents if surface changed or if decorator resolution forced it.
						if changed or forceCascade then
							if not CascadedThisDrain[nextModule] or forceCascade then
								CascadedThisDrain[nextModule] = true

								for _, dependent in ParsingHandler.GetDependents(nextModule) do
									CascadedThisDrain[dependent] = nil
									EnqueueIndex(dependent, true)
								end
							end
						end
					end
				end
			end)

			if not ok then
				warn("[Nodeal Autocomplete] Queue drain error: " .. tostring(err))
			end

			table.clear(IndexQueue)
			table.clear(QueueSet)
			table.clear(CascadedThisDrain)
			table.clear(ForceCascadeNext)

			queueIndex = 1
			queueActive = false

			if RegisterDecorator.FlushDirty then
				RegisterDecorator.FlushDirty()
			end

			if debounceThread then
				task.cancel(debounceThread)
			end

			debounceThread = task.delay(0.25, function()
				RebuildDynamiqueTypes()
				RebuildDynamiqueServices()
				RebuildDynamiqueModules()
				RebuildDynamiqueDecorators()

				local roots = CollectionService:GetTagged(utils.manifest.TagRoot)
				ParsingHandler.UpdateExecutionOrder(roots)
			end)
		end)
	end
end

local CompletionItems = {}

for _, instance: Instance in assets.CompletionItems:GetChildren() do
	if not instance:IsA("ModuleScript") then continue end
	CompletionItems[instance.Name] = require(instance)
end

local function _cleanup_export(content: { [any]: any }): ()
	for key: any, value: any in content do
		if typeof(value) ~= "table" then continue end

		_cleanup_export(value)

		if next(value) == nil then
			content[key] = nil
		end
	end
end

local function _getSimplifiedJson(data: any): string?
	return (data and next(data)) and HttpService:JSONEncode(data) or nil
end

RebuildDynamiqueTypes = function()
	local cache = {}

	for index: string, value: dict in _CompletionItems do
		cache[index] = value
	end

	for _, localCache in ModuleTypesCaches do
		for name: string, item: dict in localCache do
			cache[name] = item
		end
	end

	ExtendCall.ApplyExtensions(cache)

	dynamiqueTypes = cache
end

RebuildDynamiqueServices = function()
	local cache = {}

	for _, localCache in ModuleServiceCaches do
		for name: string, item: dict in localCache do
			cache[name] = item
		end
	end

	autoComplete.ServicesCompletions = cache
end

RebuildDynamiqueModules = function()
	local cache = {}

	for _, item: dict in ModuleModulesCaches do
		cache[item.name] = item
	end

	autoComplete.ModulesCompletions = cache
end

RebuildDynamiqueDecorators = function()
	local cache = {}

	for index: string, value: dict in Decorators do
		cache[index] = value
	end

	for _, content: {[string]: any} in DecoratorTypesCaches do
		for name: string, item: {[any]: any} in content do
			cache[name] = item
		end
	end

	dynamiqueDecorators = cache
end

-- Rend true quand la surface exportee du module a change -- c'est-a-dire quand ses dependants
-- ont une raison d'etre reanalyses. Modifier le corps d'une fonction ne change rien de ce que
-- les autres modules voient : eux n'ont besoin de savoir que ce qui sort d'ici.
Index = function(module: ModuleScript): boolean
	local wasExcluded = module:GetAttribute("ContentExcluded")
	local wasHeader = module:GetAttribute("ContentHeader")
	local wasPayload = module:GetAttribute("ContentPayload")

	local success, result = pcall(function()
		local source = module.Source
		local content, parsed, exportedTypes = ParsingHandler(source, module, "indexing")

		-- print(module, content, parsed)

		if content then
			module:SetAttribute("ContentExcluded", nil)
		else
			module:SetAttribute("ContentExcluded", true)

			module:SetAttribute("ContentHeader", nil)
			module:SetAttribute("ContentPayload", nil)

			ModuleTypesCaches[module] = nil
			ModuleServiceCaches[module] = nil
			ModuleModulesCaches[module] = nil
			ModuleParsedCaches[module] = nil
			DecoratorTypesCaches[module] = nil
			ExtendCall.ClearModule(module)
			dynamiqueExportedTypes[module.Name] = nil
			autoComplete.ModulesCompletions[module.Name] = nil
			return
		end

		--// Caching //--
		local cache_builtin = {}
		for _, value: dict in parsed do
			if not value.__builtin then continue end

			local name = value.__builtin.name
			local item = value.__builtin

			item.next = value
			item.next.__builtin = nil

			cache_builtin[name] = item
		end

		ModuleTypesCaches[module] = cache_builtin
		dynamiqueExportedTypes[module.Name] = exportedTypes

		local cache_service = {}
		for _, value: {[string]: any} in parsed do
			if not value.__services then continue end

			for _, service: {[string]: any} in value.__services do
				service.next = value
				cache_service[service.name] = service
			end
		end

		ModuleServiceCaches[module] = cache_service
		ModuleParsedCaches[module] = parsed

		local returnItem = content.__return
		local returnComp = returnItem and returnItem.completion
		local doc = (returnComp and returnComp.documentation and returnComp.documentation ~= "") and returnComp.documentation
			or (returnItem and returnItem.documentation and returnItem.documentation ~= "" and returnItem.documentation)
			or nil
		local tags = (returnComp and returnComp.tags)
			or (returnItem and returnItem.metadata and returnItem.metadata.tags)
			or nil
		local example = (returnComp and (returnComp.example or returnComp.codeSample))
			or (returnItem and returnItem.metadata and returnItem.metadata.example)
			or nil
		local hidden = (returnComp and returnComp.hidden)
			or (returnItem and returnItem.metadata and returnItem.metadata.hidden)
			or false

		local oldItem = ModuleModulesCaches[module]
		if oldItem and oldItem.name ~= module.Name then
			autoComplete.ModulesCompletions[oldItem.name] = nil
		end

		local moduleItem = {
			name = module.Name,
			type = "module",
			discovery = {
				type = "indexing",
				module = module,
			},
			completion = {
				label = module.Name,
				kind = Enum.CompletionItemKind.Module,
				detail = module.Name,
				documentation = doc,
				example = example,
				hidden = hidden,
				tags = tags,
				crossContexts = returnComp and returnComp.crossContexts,
			},
			next = content,
		}

		ModuleModulesCaches[module] = moduleItem
		autoComplete.ModulesCompletions[module.Name] = moduleItem

		DecoratorTypesCaches[module] = parsed.__decorators

		if parsed.__decorators then
			ResolveWaitingForDecorators(parsed.__decorators)
		end

		if parsed.__unresolved then
			for decoratorName in parsed.__unresolved do
				MissingDecoratorsMap[decoratorName] = MissingDecoratorsMap[decoratorName] or {}
				MissingDecoratorsMap[decoratorName][module] = true
			end
		end

		--// Attributes //--
		local datas = {
			["header"] = (content.__return and content.__return.metadata) and content.__return.metadata or {},
			["payload"] = {}
		}

		local function _extract_metadata(node: any, path: string)
			for key, value in node do
				if type(key) == "string" and key:sub(1, 2) == "__" then continue end
				if type(value) ~= "table" then continue end

				if value.type and value.metadata then
					-- CompletionItem
					if #value.metadata > 0 then
						local metadatas = {}
						for i, dec in value.metadata do
							metadatas[i] = dec
						end
						local fullPath = path == "" and key or (path .. "." .. key)
						datas.payload[fullPath] = metadatas
					end
				else
					-- Namespace
					local newPath = path == "" and key or (path .. "." .. key)
					_extract_metadata(value, newPath)
				end
			end
		end

		_extract_metadata(content, "")

		if parsed[".calls"] and next(parsed[".calls"]) then
			datas.payload[".calls"] = parsed[".calls"]
			RegisterDecorator.SetCalls(module, parsed[".calls"])
		else
			RegisterDecorator.ClearCalls(module)
		end

		_cleanup_export(datas.header)

		local collected = RegisterDecorator.GetCollected and RegisterDecorator.GetCollected(module) or (RegisterDecorator.CollectedDecorators and RegisterDecorator.CollectedDecorators[module])
		if collected and next(collected) then
			datas.payload[".collected"] = collected
		elseif parsed.__decorators and next(parsed.__decorators) and wasPayload then
			local prevOk, prevDec = pcall(HttpService.JSONDecode, HttpService, wasPayload)
			if prevOk and type(prevDec) == "table" and prevDec[".collected"] then
				datas.payload[".collected"] = prevDec[".collected"]
			end
		end

		local isDefiningModule = (parsed.__decorators and next(parsed.__decorators) ~= nil)
			or (RegisterDecorator.DefiningModules and RegisterDecorator.DefiningModules[module] == true)

		if isDefiningModule then
			local aggCalls = RegisterDecorator.GetAggregatedCalls and RegisterDecorator.GetAggregatedCalls(module)
			if aggCalls and next(aggCalls) then
				datas.payload[".calls"] = aggCalls
			else
				datas.payload[".calls"] = nil
			end
		end

		module:SetAttribute("ContentHeader", _getSimplifiedJson(datas.header))
		module:SetAttribute("ContentPayload", _getSimplifiedJson(datas.payload))
	end)

	if not success then
		warn("Failed to index '" .. module:GetFullName() .. "' for '" .. (result or "unknown") .. "'")
		ModuleTypesCaches[module] = nil
		ModuleServiceCaches[module] = nil
		ModuleModulesCaches[module] = nil
		DecoratorTypesCaches[module] = nil
		ExtendCall.ClearModule(module)
		dynamiqueExportedTypes[module.Name] = nil
		autoComplete.ModulesCompletions[module.Name] = nil

		-- Une analyse ratee ne dit rien de la surface : on propage, faute de mieux.
		return true
	end

	return module:GetAttribute("ContentExcluded") ~= wasExcluded
		or module:GetAttribute("ContentHeader") ~= wasHeader
		or module:GetAttribute("ContentPayload") ~= wasPayload
end

findExportedTypeOnDemand = function(typeName: string): any?
	for _, expTypes in dynamiqueExportedTypes do
		if expTypes and expTypes[typeName] then
			return expTypes[typeName]
		end
	end

	if missedExportedTypes[typeName] then
		return nil
	end

	local taggedRoots = CollectionService:GetTagged(utils.manifest.TagRoot)
	local function scanModule(inst: Instance): any?
		if not inst:IsA("ModuleScript") then return nil end
		if dynamiqueExportedTypes[inst.Name] then return nil end

		local pcallOk, src = pcall(function() return inst.Source end)
		if pcallOk and type(src) == "string" and string.find(src, "type%s+" .. typeName .. "%f[%A]") then
			Index(inst)
			if dynamiqueExportedTypes[inst.Name] and dynamiqueExportedTypes[inst.Name][typeName] then
				return dynamiqueExportedTypes[inst.Name][typeName]
			end
		end
		return nil
	end

	for _, root in taggedRoots do
		local res = scanModule(root)
		if res then return res end

		for _, inst in root:GetDescendants() do
			local r = scanModule(inst)
			if r then return r end
		end
	end

	missedExportedTypes[typeName] = true
	return nil
end

TypeResolver.FindExportedType = findExportedTypeOnDemand

RequestIndex = function(module: ModuleScript)
	table.clear(missedExportedTypes)
	if not indexing_toggled then return end

	if IndexThreads[module] then
		task.cancel(IndexThreads[module])
	end

	IndexThreads[module] = task.delay(0.5, function()
		IndexThreads[module] = nil

		if not module.Parent then return end 

		CascadedThisDrain[module] = nil
		EnqueueIndex(module)
	end)
end

local function UnregisterRoot(root: Instance)
	table.clear(missedExportedTypes)
	if not RootConnectors[root] then return end

	RootConnectors[root]:Destroy()
	RootConnectors[root] = nil

	local cacheChanged = false

	for _, instance in root:GetDescendants() do
		if instance:IsA("ModuleScript") then
			RegisterDecorator.ClearTarget(instance)
			RegisterDecorator.ClearDefiningModule(instance)
			RegisterDecorator.ClearCalls(instance)
			ParsingHandler.ClearModuleDecorators(instance)
			ExtendCall.ClearModule(instance)
			TypeResolver.ClearExtensions(instance)

			for _, map in MissingDecoratorsMap do
				map[instance] = nil
			end

			if IndexThreads[instance] then
				task.cancel(IndexThreads[instance])
				IndexThreads[instance] = nil
			end

			dynamiqueExportedTypes[instance.Name] = nil

			if ModuleTypesCaches[instance] or ModuleServiceCaches[instance] or ModuleModulesCaches[instance] or DecoratorTypesCaches[instance] or ModuleParsedCaches[instance] then
				ModuleTypesCaches[instance] = nil
				ModuleServiceCaches[instance] = nil
				ModuleModulesCaches[instance] = nil
				ModuleParsedCaches[instance] = nil
				DecoratorTypesCaches[instance] = nil
				cacheChanged = true
			end

		end
	end

	if cacheChanged then
		RebuildDynamiqueTypes()
		RebuildDynamiqueServices()
		RebuildDynamiqueModules()
		RebuildDynamiqueDecorators()
	end
end

local function RegisterRoot(root: Instance, deferEnqueuing: boolean?)
	if root:IsAncestorOf(workspace) then return nil, nil end

	local connector = utils.connector.new()

	local function ListenToModule(instance: Instance)
		table.clear(missedExportedTypes)
		if not instance:IsA("ModuleScript") or connector[instance] then return end

		local pcallOk, src = pcall(function() return instance.Source end)
		local isProvider = pcallOk and type(src) == "string" and string.find(src, "RegisterDecorator", 1, true) ~= nil

		EnqueueIndex(instance, isProvider)

		-- Seul le module touche est remis en file. Ses dependants ne suivent que si sa surface
		-- exportee a reellement change, et c'est la boucle de vidage qui s'en charge : taper
		-- dans le corps d'une fonction ne concerne personne d'autre.
		--
		-- Avant, chaque frappe relancait le module plus tous ses dependants transitifs. Mesure
		-- sur ce depot : modifier RoundConstants reanalysait 22 modules, soit deux secondes de
		-- Studio fige a chaque sauvegarde.
		local modConnector = utils.connector.new()
		modConnector:Track(instance:GetPropertyChangedSignal("Source"), function()
			RequestIndex(instance)
		end)
		modConnector:Track(instance:GetPropertyChangedSignal("Name"), function()
			RequestIndex(instance)
		end)
		connector:Track(modConnector, nil, instance)
	end

	connector:Track(root.DescendantAdded, ListenToModule)

	local decoratorProviders = {}
	local otherModules = {}

	local function categorizeModule(instance: Instance)
		if not instance:IsA("ModuleScript") then return end
		local pcallOk, src = pcall(function() return instance.Source end)
		if pcallOk and type(src) == "string" and string.find(src, "RegisterDecorator", 1, true) ~= nil then
			table.insert(decoratorProviders, instance)
		else
			table.insert(otherModules, instance)
		end
	end

	if root:IsA("ModuleScript") then
		categorizeModule(root)
	end

	for _, instance: Instance in root:GetDescendants() do
		categorizeModule(instance)
	end

	local function trackModuleSignals(mod: ModuleScript)
		if connector[mod] then return end
		local modConnector = utils.connector.new()
		modConnector:Track(mod:GetPropertyChangedSignal("Source"), function()
			RequestIndex(mod)
		end)
		modConnector:Track(mod:GetPropertyChangedSignal("Name"), function()
			RequestIndex(mod)
		end)
		connector:Track(modConnector, nil, mod)
	end

	if deferEnqueuing then
		for _, mod in decoratorProviders do
			trackModuleSignals(mod)
		end
		for _, mod in otherModules do
			trackModuleSignals(mod)
		end
	else
		for _, mod in decoratorProviders do
			ListenToModule(mod)
		end
		for _, mod in otherModules do
			ListenToModule(mod)
		end
	end

	connector:Track(root.DescendantRemoving, function(instance: Instance)
		if not connector[instance] then return end
		connector:Disconnect(instance)

		if instance:IsA("ModuleScript") then
			RegisterDecorator.ClearTarget(instance)
			RegisterDecorator.ClearDefiningModule(instance)
			RegisterDecorator.ClearCalls(instance)
			ParsingHandler.ClearModuleDecorators(instance)
			TypeResolver.ClearExtensions(instance)

			for _, map in MissingDecoratorsMap do
				map[instance] = nil
			end

			if IndexThreads[instance] then
				task.cancel(IndexThreads[instance])
				IndexThreads[instance] = nil
			end

			dynamiqueExportedTypes[instance.Name] = nil

			if ModuleTypesCaches[instance] then
				ModuleTypesCaches[instance] = nil
				RebuildDynamiqueTypes()
			end

			if ModuleServiceCaches[instance] then
				ModuleServiceCaches[instance] = nil
				RebuildDynamiqueServices()
			end

			if ModuleModulesCaches[instance] then
				ModuleModulesCaches[instance] = nil
				RebuildDynamiqueModules()
			end

			if DecoratorTypesCaches[instance] then
				DecoratorTypesCaches[instance] = nil
				RebuildDynamiqueDecorators()
			end
		end
	end)

	connector:Track(root.Destroying, function()
		UnregisterRoot(root)
	end)

	RootConnectors[root] = connector

	if deferEnqueuing then
		return decoratorProviders, otherModules
	end
	return nil, nil
end

local function updateToggle()
	local success, callback = pcall(function()
		ScriptEditorService:DeregisterAutocompleteCallback(IntelliSenseId)
	end)

	if toggeled then
		local success, callback = pcall(function()
			ScriptEditorService:RegisterAutocompleteCallback(IntelliSenseId, 255, AutocompleteCallback)
		end)
	end
end

--// Callback //--
function autoComplete.clicked(self: any, widget: string)
	local widget = self.widgets[widget]

	toggeled = not toggeled
	widget.button.Icon = toggeled and "rbxassetid://4458804262" or "rbxassetid://4458801905"

	updateToggle()
end

function autoComplete.Init(self: any, widget: string)
	class = self
	plugin = class.plugin

	self.widgets[widget].noButton = true

	local success, callback = pcall(function()
		ScriptEditorService:DeregisterAutocompleteCallback(IntelliSenseId)
	end)

	updateToggle()

	CollectionService:GetInstanceAddedSignal(utils.manifest.TagRoot):Connect(function(root: Instance)
		RegisterRoot(root, false)
	end)
	CollectionService:GetInstanceRemovedSignal(utils.manifest.TagRoot):Connect(UnregisterRoot)

	local allProviders = {}
	local allOthers = {}

	local taggedRoots = CollectionService:GetTagged(utils.manifest.TagRoot)
	for _, root: Instance in taggedRoots do
		local providers, others = RegisterRoot(root, true)
		if providers then
			for _, mod in providers do
				table.insert(allProviders, mod)
			end
		end
		if others then
			for _, mod in others do
				table.insert(allOthers, mod)
			end
		end
	end

	-- Index ALL decorator providers across ALL roots synchronously FIRST
	for _, mod in allProviders do
		Index(mod)
	end

	RebuildDynamiqueTypes()
	RebuildDynamiqueServices()
	RebuildDynamiqueModules()
	RebuildDynamiqueDecorators()

	-- Enqueue all standard modules across ALL roots SECOND
	for _, mod in allOthers do
		EnqueueIndex(mod, false)
	end

	plugin.Unloading:Connect(function()
		indexing_toggled = false
	end)
end

return autoComplete