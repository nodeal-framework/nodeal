--!native
--!optimize 2

--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local ApiDump = require(script.Parent.ApiDump)

local TypeResolver = {}
TypeResolver.Registry = {}

local EnumPropertyKind = nil
pcall(function()
	EnumPropertyKind = Enum.CompletionItemKind.Property
end)

local function createCompletionItem(parser: any, config: any)
	if parser and type(parser.CreateCompletionItem) == "function" then
		return parser:CreateCompletionItem(config)
	end
	return {
		name = config.name,
		table = config.table or config.tableName,
		type = config.type or "unknown",
		completion = {
			label = config.label or config.name,
			kind = config.kind or EnumPropertyKind,
			detail = config.detail or config.name,
			documentation = config.documentation or "",
		},
		next = config.next,
	}
end

local function ResolveStringLiteralUnion(t, parser)
	if not t then return {} end
	if t.type == "literal" and t.literalType == "string" then
		return { t.value }
	elseif t.type == "union" then
		local values = {}
		for _, subT in t.types do
			local subVals = ResolveStringLiteralUnion(subT, parser)
			for _, v in subVals do
				table.insert(values, v)
			end
		end
		return values
	elseif t.type == "reference" then
		local resolved = parser.types[t.name]
		if resolved then
			return ResolveStringLiteralUnion(resolved, parser)
		end
	end
	return {}
end
TypeResolver.ResolveStringLiteralUnion = ResolveStringLiteralUnion

local function ResolvePath(pathStr: string, currentModule: ModuleScript?): Instance?
	pathStr = pathStr:match("^%s*(.-)%s*$")
	local first = pathStr:sub(1, 1)
	local last = pathStr:sub(-1, -1)
	if (first == '"' and last == '"') or (first == "'" and last == "'") or (first == "`" and last == "`") then
		pathStr = pathStr:sub(2, -2)
	end
	pathStr = pathStr:match("^%s*(.-)%s*$")

	local current: Instance? = nil
	local segments = {}

	local i = 1
	local len = #pathStr
	while i <= len do
		local s, e = pathStr:find("^:GetService%s*%b()", i)
		if s then
			local serviceName = pathStr:sub(s, e):match("%(%s*[\"'(]?([%w_]+)[\"')]?%s*%)")
			if serviceName then
				table.insert(segments, serviceName)
			end
			i = e + 1
		else
			local char = pathStr:sub(i, i)
			if char == "." or char == ":" then
				i += 1
			elseif char == '"' or char == "'" or char == "`" then
				local quote = char
				i += 1
				local start = i
				while i <= len and pathStr:sub(i, i) ~= quote do
					i += 1
				end
				table.insert(segments, pathStr:sub(start, i - 1))
				i += 1
			elseif pathStr:sub(i):match("^parent") or pathStr:sub(i):match("^Parent") then
				table.insert(segments, "Parent")
				i += #("Parent")
			else
				local start = i
				while i <= len and pathStr:sub(i, i):match("[%w_]") do
					i += 1
				end
				local val = pathStr:sub(start, i - 1)
				if val ~= "" then
					table.insert(segments, val)
				else
					i += 1
				end
			end
		end
	end

	if #segments == 0 then return nil end

	local startIndex = 1
	if segments[1] == "game" then
		current = game
		startIndex = 2
	elseif segments[1] == "workspace" or segments[1] == "Workspace" then
		current = workspace
		startIndex = 2
	elseif segments[1] == "script" then
		current = currentModule
		startIndex = 2
	else
		current = currentModule or game
	end

	for idx = startIndex, #segments do
		if not current then break end
		local seg = segments[idx]
		if seg == "Parent" then
			current = current.Parent
		else
			local nextInstance = current:FindFirstChild(seg)
			if not nextInstance and current == game then
				pcall(function()
					nextInstance = game:GetService(seg)
				end)
			end
			current = nextInstance
		end
	end

	return current
end
TypeResolver.ResolvePath = ResolvePath

local function BuildInstanceTreeFields(instance: Instance, parser): { [string]: any }
	local fields = {}
	local baseCompletion = ApiDump:GetAutoCompletion(instance.ClassName) or {}
	for k, v in baseCompletion do
		fields[k] = v
	end

	for _, child in instance:GetChildren() do
		local childFields = BuildInstanceTreeFields(child, parser)
		fields[child.Name] = createCompletionItem(parser, {
			name = child.Name,
			type = "variable",
			kind = Enum.CompletionItemKind.Field,
			detail = child.ClassName,
			next = childFields
		})
	end
	return fields
end
TypeResolver.BuildInstanceTreeFields = BuildInstanceTreeFields

--// Dynamic Registry Loading //--
if script and script.Parent and script.Parent:FindFirstChild("Types") then
	for _, module: ModuleScript in script.Parent.Types:GetChildren() do
		if not module:IsA("ModuleScript") then continue end
		TypeResolver.Registry[module.Name] = require(module)
	end
end

--// Type Extensions Registry //--
TypeResolver.ExtendRegistry = {} :: { [string]: { [string]: any } }
TypeResolver.ExtensionsByModule = {} :: { [ModuleScript]: { [string]: { [string]: any } } }

function TypeResolver.RegisterExtension(baseType: string, subType: string, data: any?, originModule: ModuleScript?)
	TypeResolver.ExtendRegistry[baseType] = TypeResolver.ExtendRegistry[baseType] or {}
	TypeResolver.ExtendRegistry[baseType][subType] = data or true

	if originModule then
		TypeResolver.ExtensionsByModule[originModule] = TypeResolver.ExtensionsByModule[originModule] or {}
		TypeResolver.ExtensionsByModule[originModule][baseType] = TypeResolver.ExtensionsByModule[originModule][baseType] or {}
		TypeResolver.ExtensionsByModule[originModule][baseType][subType] = data or true
	end
end

function TypeResolver.ClearExtensions(originModule: ModuleScript)
	local moduleExts = TypeResolver.ExtensionsByModule[originModule]
	if not moduleExts then return end
	TypeResolver.ExtensionsByModule[originModule] = nil

	local newRegistry = {}
	for mod, exts in TypeResolver.ExtensionsByModule do
		for baseType, subs in exts do
			newRegistry[baseType] = newRegistry[baseType] or {}
			for subType, val in subs do
				newRegistry[baseType][subType] = val
			end
		end
	end
	TypeResolver.ExtendRegistry = newRegistry
end

--// Public Resolver Function //--
function TypeResolver.Resolve(parsedType: any, parser: any, visited: { [string]: boolean }?): ({ [string]: any }, string)
	if not parsedType then
		return {}, "any"
	end

	if type(parsedType) == "string" then
		parsedType = { kind = "reference", name = parsedType, path = { parsedType } }
	end

	visited = visited or {}

	local k = parsedType.kind or parsedType.type


	if k == "basic" then
		return {}, parsedType.name
	elseif k == "literal" then
		return {}, tostring(parsedType.value)
	elseif k == "optional" then
		local innerFields, innerName = TypeResolver.Resolve(parsedType.inner, parser, visited)
		return innerFields, (innerName or "any") .. "?"
	elseif k == "reference" then
		if parsedType.name and visited[parsedType.name] then
			return {}, parsedType.name
		end

		if parsedType.path and #parsedType.path > 1 then
			local modName = parsedType.path[1]
			local typeName = parsedType.path[2]
			local imported = parser and parser.importedTypes and parser.importedTypes[modName]
			if imported and imported[typeName] then
				visited[typeName] = true
				local resFields, resName = TypeResolver.Resolve(imported[typeName], parser, visited)
				visited[typeName] = nil
				return resFields, resName
			end
		end

		local localType = parser and parser.types and parser.types[parsedType.name]
		if localType then
			visited[parsedType.name] = true
			local resFields, resName = TypeResolver.Resolve(localType, parser, visited)
			visited[parsedType.name] = nil
			return resFields, resName
		end

		local localTable = parser and parser.tables and parser.tables[parsedType.name]
		if localTable then
			return localTable, parsedType.name
		end

		if TypeResolver.ExportedTypes then
			for _, expMap in TypeResolver.ExportedTypes do
				if expMap and expMap[parsedType.name] and not visited[parsedType.name] then
					visited[parsedType.name] = true
					local resFields, resName = TypeResolver.Resolve(expMap[parsedType.name], parser, visited)
					visited[parsedType.name] = nil
					return resFields, resName
				end
			end
		end

		local apiFields = ApiDump:GetAutoCompletion(parsedType.name)
		if apiFields then
			return apiFields, parsedType.name
		end

		if TypeResolver.FindExportedType and not visited[parsedType.name] then
			local onDemandAST = TypeResolver.FindExportedType(parsedType.name)
			if onDemandAST then
				visited[parsedType.name] = true
				local resFields, resName = TypeResolver.Resolve(onDemandAST, parser, visited)
				visited[parsedType.name] = nil
				return resFields, resName
			end
		end

		return {}, parsedType.name
	elseif k == "table" then
		local fields = {}
		local parts = {}
		for propName, propInfo in parsedType.fields do
			local resolvedFields, propTypeName = TypeResolver.Resolve(propInfo.type, parser, visited)
			fields[propName] = createCompletionItem(parser, {
				name = propName,
				type = (propInfo.type.kind == "function" or propInfo.type.type == "function") and "function" or "variable",
				kind = EnumPropertyKind,
				detail = propTypeName or "any",
				next = resolvedFields
			})
			table.insert(parts, propName .. ": " .. (propTypeName or "any"))
		end

		if parsedType.indexer then
			local _, keyName = TypeResolver.Resolve(parsedType.indexer.key, parser, visited)
			local valFields, valName = TypeResolver.Resolve(parsedType.indexer.value, parser, visited)
			table.insert(parts, "[" .. keyName .. "]: " .. valName)

			local function addLiteralKeys(kType)
				local kt = kType.kind or kType.type
				if kt == "literal" and kType.literalType == "string" then
					fields[kType.value] = createCompletionItem(parser, {
						name = kType.value,
						type = "variable",
						kind = EnumPropertyKind,
						detail = valName,
						next = valFields
					})
				elseif kt == "union" then
					for _, uType in kType.types do
						addLiteralKeys(uType)
					end
				end
			end

			addLiteralKeys(parsedType.indexer.key)
		end

		local typeName = "{ " .. table.concat(parts, ", ") .. " }"
		return fields, typeName
	elseif k == "array" then
		local _, elemTypeName = TypeResolver.Resolve(parsedType.elementType, parser, visited)
		return {}, "{" .. elemTypeName .. "}"
	elseif k == "union" then
		local fields = {}
		local parts = {}
		for _, t in parsedType.types do
			local resolved, name = TypeResolver.Resolve(t, parser, visited)
			table.insert(parts, name)
			for k, v in resolved do
				fields[k] = v
			end
		end
		return fields, table.concat(parts, " | ")
	elseif k == "intersection" then
		local fields = {}
		local parts = {}
		for _, t in parsedType.types do
			local resolved, name = TypeResolver.Resolve(t, parser, visited)
			table.insert(parts, name)
			for k, v in resolved do
				fields[k] = v
			end
		end
		return fields, table.concat(parts, " & ")
	elseif k == "function" then
		local argParts = {}
		for _, arg in parsedType.arguments do
			local _, argTypeName = TypeResolver.Resolve(arg.type, parser, visited)
			table.insert(argParts, (arg.name and (arg.name .. ": ") or "") .. (argTypeName or "any"))
		end
		local returnFields, returnTypeName = TypeResolver.Resolve(parsedType.returns, parser, visited)
		local typeName = "(" .. table.concat(argParts, ", ") .. ") -> " .. (returnTypeName or "any")
		return returnFields, typeName
	elseif k == "generic" then
		local handler = TypeResolver.Registry[parsedType.name]
		if handler and handler.resolve then
			return handler.resolve(parsedType.args, parser)
		end

		local baseType = parser and parser.types and parser.types[parsedType.name]
		if baseType then
			if visited[parsedType.name] then
				return {}, parsedType.name .. "<...>"
			end
			visited[parsedType.name] = true
			local resFields, resName = TypeResolver.Resolve(baseType, parser, visited)
			visited[parsedType.name] = nil
			return resFields, resName
		end

		return {}, parsedType.name .. "<...>"
	end

	return {}, "any"
end

function TypeResolver.ResolveAST(parsedType: any, parser: any, visited: {[string]: boolean}?): any
	if not parsedType then return nil end

	local k = parsedType.kind or parsedType.type
	visited = visited or {}

	if k == "reference" then
		if parsedType.path and #parsedType.path == 1 then
			local refName = parsedType.name
			if not visited[refName] and parser and parser.types and parser.types[refName] then
				visited[refName] = true
				local resolved = TypeResolver.ResolveAST(parser.types[refName], parser, visited)
				visited[refName] = nil
				return resolved
			end

			if not visited[refName] and parser and parser.tables and parser.tables[refName] then
				visited[refName] = true
				local fields = {}
				for k, v in parser.tables[refName] do
					if type(k) == "string" and k:sub(1, 2) == "__" then continue end
					if type(v) == "table" and v.name then
						fields[k] = { 
							optional = false, 
							type = { kind = "reference", name = v.type == "function" and "function" or "any", path = {v.type == "function" and "function" or "any"} } 
						}
					end
				end
				visited[refName] = nil
				return { kind = "table", fields = fields }
			end
		end
		return parsedType
	elseif k == "optional" then
		return { kind = "optional", inner = TypeResolver.ResolveAST(parsedType.inner, parser, visited) }
	elseif k == "array" then
		return { kind = "array", element = TypeResolver.ResolveAST(parsedType.element or parsedType.elementType, parser, visited) }
	elseif k == "table" then
		local fields = {}
		if parsedType.fields then
			for key, v in parsedType.fields do
				fields[key] = { optional = v.optional, type = TypeResolver.ResolveAST(v.type, parser, visited) }
			end
		end
		local indexer = nil
		if parsedType.indexer then
			indexer = { 
				key = TypeResolver.ResolveAST(parsedType.indexer.key, parser, visited), 
				value = TypeResolver.ResolveAST(parsedType.indexer.value, parser, visited) 
			}
		end
		return { kind = "table", fields = fields, indexer = indexer }
	elseif k == "union" then
		local kinds = {}
		for _, t in (parsedType.types or parsedType.kinds or {}) do
			table.insert(kinds, TypeResolver.ResolveAST(t, parser, visited))
		end
		return { kind = "union", types = kinds }
	elseif k == "intersection" then
		local kinds = {}
		for _, t in (parsedType.types or parsedType.kinds or {}) do
			table.insert(kinds, TypeResolver.ResolveAST(t, parser, visited))
		end
		return { kind = "intersection", types = kinds }
	elseif k == "function" then
		local args = {}
		if parsedType.arguments then
			for _, arg in parsedType.arguments do
				table.insert(args, { name = arg.name, type = TypeResolver.ResolveAST(arg.type, parser, visited) })
			end
		end
		return { 
			kind = "function", 
			name = parsedType.name,
			generics = parsedType.generics,
			arguments = args, 
			returns = TypeResolver.ResolveAST(parsedType.returns, parser, visited) 
		}
	elseif k == "variadic" then
		return { kind = "variadic", type = TypeResolver.ResolveAST(parsedType.type, parser, visited) }
	elseif k == "generic" then
		local args = {}
		for _, arg in (parsedType.args or {}) do
			table.insert(args, TypeResolver.ResolveAST(arg, parser, visited))
		end
		return { kind = "generic", name = parsedType.name, args = args }
	elseif k == "tuple" then
		local elements = {}
		for _, el in (parsedType.elements or {}) do
			table.insert(elements, TypeResolver.ResolveAST(el, parser, visited))
		end
		return { kind = "tuple", elements = elements }
	end

	return parsedType
end

return TypeResolver
