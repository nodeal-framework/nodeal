local TypeParser = (script and script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("TypeParser")) and require(script.Parent.Parent.TypeParser) or require("../TypeParser")

local exports = {
	["documentation"] = function(item)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		return (item.completion and item.completion.documentation) or ""
	end,
	["name"] = function(item)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		local ast = TypeParser.ParseSignature(item)
		return (ast and ast.name) or item.name or ""
	end,
	["arguments"] = function(item, option: string?)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		local ast = TypeParser.ParseSignature(item)

		local args = ast and ast.arguments or {}

		local resolvedArgs = {}
		if option == nil or option == "simple" then
			for _, arg in args do
				table.insert(resolvedArgs, {
					name = arg.name,
					type = arg.type
				})
			end
		elseif option == "advanced" then
			local TypeResolver = require(script.Parent.Parent.TypeResolver)
			for _, arg in args do
				table.insert(resolvedArgs, {
					name = arg.name,
					type = TypeResolver.ResolveAST(arg.type, item.parser)
				})
			end
		end
		args = resolvedArgs

		if item.methodes and table.find(item.methodes, ":") then
			table.insert(args, 1, {
				name = "self",
				type = { kind = "reference", name = "any", path = {"any"} }
			})
		end
		return args
	end,
	["returns"] = function(item, option: string?)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		local ast = TypeParser.ParseSignature(item)

		local returns = ast and ast.returns
		if returns and (option == "advanced" or option == "advenced") then
			local TypeResolver = require(script.Parent.Parent.TypeResolver)
			returns = TypeResolver.ResolveAST(returns, item.parser)
		end
		return returns or { kind = "basic", name = "void" }
	end,
	["prototype"] = function(item)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		return item.prototype or ""
	end,
	["usages"] = function(item)
		if not item.discovery or item.discovery.type ~= "indexing" or item.type ~= "function" then return nil end
		local funcName = item.name
		if funcName and item.parser and item.parser.trackedUsages then
			item.parser.trackedUsages[funcName] = true
			item.isTrackedForUsages = true
		end
		return { signature = "usages" }
	end,
}

--// Collected Storage //--
-- [definingModule][decoratorName][targetModule][methodName] = record
local CollectedByModule: { [ModuleScript]: { [string]: { [ModuleScript]: { [string]: any } } } } = {}
local DefiningModules: { [ModuleScript]: boolean } = {}
-- [targetModule][definingModule] = true (Inverse index O(1) for ClearTarget)
local TargetToDefinitions: { [ModuleScript]: { [ModuleScript]: boolean } } = {}
-- Set of definingModules whose ContentPayload must be synchronized
local DirtyDefiningModules: { [ModuleScript]: boolean } = {}

local syncThread = nil

local ServicesByModule: { [ModuleScript]: { [string]: boolean } } = {}
local ModulesByModule: { [ModuleScript]: { [string]: boolean } } = {}
local AllCallsByCallingModule: { [ModuleScript]: { [string]: any } } = {}

local GetCollected: (definingModule: ModuleScript) -> { [string]: { any } }
local GetAggregatedCalls: (definingModule: ModuleScript) -> { [string]: any }
local SetCalls: (callingModule: ModuleScript, calls: { [string]: any }) -> ()
local ClearCalls: (callingModule: ModuleScript) -> ()
local SyncPayload: (definingModule: ModuleScript) -> ()
local MarkDirty: (definingModule: ModuleScript) -> ()

GetCollected = function(definingModule: ModuleScript): { [string]: { any } }
	local result = {}
	local decMap = CollectedByModule[definingModule]
	if not decMap then return result end

	for decName, targetMap in decMap do
		local list = {}
		for targetMod, methods in targetMap do
			if targetMod.Parent then
				for _, record in methods do
					if ServicesByModule[targetMod] and type(record[2]) == "table" then
						for srvName in ServicesByModule[targetMod] do
							if not table.find(record[2], srvName) then
								table.insert(record[2], srvName)
							end
						end
					end
					if ModulesByModule[targetMod] and type(record[1]) == "table" then
						for modName in ModulesByModule[targetMod] do
							if not table.find(record[1], modName) then
								table.insert(record[1], modName)
							end
						end
					end

					local recordCopy = {}
					for k, v in record do
						if (k == 1 or k == 2 or k == 5) and type(v) == "table" then
							local tblCopy = {}
							for sK, sV in v do
								tblCopy[sK] = sV
							end
							recordCopy[k] = tblCopy
						else
							recordCopy[k] = v
						end
					end
					table.insert(list, recordCopy)
				end
			else
				targetMap[targetMod] = nil
				ServicesByModule[targetMod] = nil
				ModulesByModule[targetMod] = nil
				TargetToDefinitions[targetMod] = nil
			end
		end
		if #list > 0 then
			result[decName] = list
		end
	end

	return result
end

local function getTrackedMethodsForDefiningModule(definingModule: ModuleScript): { [string]: boolean }
	local trackedMethods = {}
	local decMap = CollectedByModule[definingModule]
	if not decMap then return trackedMethods end

	for _, targetMap in decMap do
		for targetMod, methods in targetMap do
			if targetMod.Parent then
				for methodName, entry in methods do
					local exports = entry[5]
					if exports and exports.usages then
						trackedMethods[targetMod.Name .. "." .. methodName] = true
						trackedMethods[targetMod.Name .. ":" .. methodName] = true

						local modNames = entry[1]
						if type(modNames) == "table" then
							for _, mName in modNames do
								if type(mName) == "string" then
									trackedMethods[mName .. "." .. methodName] = true
									trackedMethods[mName .. ":" .. methodName] = true
								end
							end
						end

						local srvNames = entry[2]
						if type(srvNames) == "table" then
							for _, sName in srvNames do
								if type(sName) == "string" then
									trackedMethods[sName .. "." .. methodName] = true
									trackedMethods[sName .. ":" .. methodName] = true
								end
							end
						end
					end
				end
			end
		end
	end

	return trackedMethods
end

GetAggregatedCalls = function(definingModule: ModuleScript): { [string]: any }
	if not definingModule or (not DefiningModules[definingModule] and not CollectedByModule[definingModule]) then
		return {}
	end

	local trackedMethods = getTrackedMethodsForDefiningModule(definingModule)
	if not next(trackedMethods) then
		return {}
	end

	local result = {}
	for callingMod, modCalls in AllCallsByCallingModule do
		if not callingMod.Parent then
			AllCallsByCallingModule[callingMod] = nil
			continue
		end

		if type(modCalls) ~= "table" or not next(modCalls) then
			continue
		end

		local filteredModCalls = {}
		for lineStr, lineCalls in modCalls do
			if type(lineCalls) == "table" then
				local filteredLine = {}
				for funcName, callData in lineCalls do
					if trackedMethods[funcName] and callData and callData.captured == true then
						filteredLine[funcName] = { captured = true }
					end
				end
				if next(filteredLine) then
					filteredModCalls[tostring(lineStr)] = filteredLine
				end
			end
		end

		if next(filteredModCalls) then
			local modName = callingMod.Name
			if not result[modName] then
				result[modName] = filteredModCalls
			else
				for lStr, lCalls in filteredModCalls do
					result[modName][lStr] = lCalls
				end
			end
		end
	end

	return result
end

SyncPayload = function(definingModule: ModuleScript)
	if not definingModule or not definingModule.Parent then return end
	local HttpService = game:GetService("HttpService")
	local ok, currentPayload = pcall(function()
		local raw = definingModule:GetAttribute("ContentPayload")
		return raw and HttpService:JSONDecode(raw) or {}
	end)
	if ok and type(currentPayload) == "table" then
		local collected = GetCollected(definingModule)
		if next(collected) then
			currentPayload[".collected"] = collected
		else
			currentPayload[".collected"] = nil
		end

		local aggregatedCalls = GetAggregatedCalls(definingModule)
		if next(aggregatedCalls) then
			currentPayload[".calls"] = aggregatedCalls
		else
			currentPayload[".calls"] = nil
		end

		local newRaw = nil
		if next(currentPayload) then
			local encOk, encoded = pcall(HttpService.JSONEncode, HttpService, currentPayload)
			if encOk then
				newRaw = encoded
			else
				warn("[RegisterDecorator] Failed to JSONEncode ContentPayload for " .. definingModule:GetFullName() .. ": " .. tostring(encoded))
			end
		end

		local currentRaw = definingModule:GetAttribute("ContentPayload")
		if currentRaw ~= newRaw then
			local setOk, setErr = pcall(function()
				definingModule:SetAttribute("ContentPayload", newRaw)
			end)
			if not setOk then
				warn("[RegisterDecorator] Failed to SetAttribute ContentPayload on " .. definingModule:GetFullName() .. ": " .. tostring(setErr))
			end
		end
	end
end

MarkDirty = function(definingModule: ModuleScript)
	if not definingModule or not definingModule.Parent then return end
	DirtyDefiningModules[definingModule] = true
	if not syncThread then
		syncThread = task.defer(function()
			syncThread = nil
			local toProcess = DirtyDefiningModules
			DirtyDefiningModules = {}
			for defMod in toProcess do
				SyncPayload(defMod)
			end
		end)
	end
end

local function FlushDirty()
	if syncThread then
		task.cancel(syncThread)
		syncThread = nil
	end
	local toProcess = DirtyDefiningModules
	DirtyDefiningModules = {}
	for defMod in toProcess do
		SyncPayload(defMod)
	end
end

local function AddService(targetModule: ModuleScript, serviceName: string, tableName: string?)
	if not targetModule or type(serviceName) ~= "string" then return end

	ServicesByModule[targetModule] = ServicesByModule[targetModule] or {}
	ServicesByModule[targetModule][serviceName] = true

	local defs = TargetToDefinitions[targetModule]
	if defs then
		for definingModule in defs do
			local decMap = CollectedByModule[definingModule]
			if decMap then
				for decName, targetMap in decMap do
					local methods = targetMap[targetModule]
					if methods then
						for _, entry in methods do
							local matchesTable = true
							if tableName then
								local modList = entry[1]
								if type(modList) == "table" and #modList > 0 then
									matchesTable = table.find(modList, tableName) ~= nil or table.find(modList, targetModule.Name) ~= nil
								end
							end

							if matchesTable then
								local srvList = entry[2]
								if type(srvList) == "table" and not table.find(srvList, serviceName) then
									table.insert(srvList, serviceName)
									MarkDirty(definingModule)
								end
							end
						end
					end
				end
			end
		end
	end
end

local function AddModule(targetModule: ModuleScript, moduleName: string, tableName: string?)
	if not targetModule or type(moduleName) ~= "string" then return end

	ModulesByModule[targetModule] = ModulesByModule[targetModule] or {}
	ModulesByModule[targetModule][moduleName] = true

	local defs = TargetToDefinitions[targetModule]
	if defs then
		for definingModule in defs do
			local decMap = CollectedByModule[definingModule]
			if decMap then
				for decName, targetMap in decMap do
					local methods = targetMap[targetModule]
					if methods then
						for _, entry in methods do
							local matchesTable = true
							if tableName then
								local modList = entry[1]
								if type(modList) == "table" and #modList > 0 then
									matchesTable = table.find(modList, tableName) ~= nil or table.find(modList, targetModule.Name) ~= nil
								end
							end

							if matchesTable then
								local modList = entry[1]
								if type(modList) == "table" and not table.find(modList, moduleName) then
									table.insert(modList, moduleName)
									MarkDirty(definingModule)
								end
							end
						end
					end
				end
			end
		end
	end
end

local function ClearTarget(targetModule: ModuleScript)
	ServicesByModule[targetModule] = nil
	ModulesByModule[targetModule] = nil

	local defs = TargetToDefinitions[targetModule]
	if not defs then return end

	for definingModule in defs do
		local decMap = CollectedByModule[definingModule]
		if decMap then
			for decName, targetMap in decMap do
				if targetMap[targetModule] then
					targetMap[targetModule] = nil
					MarkDirty(definingModule)
				end
			end
		end
	end

	TargetToDefinitions[targetModule] = nil
end

local function ClearDefiningModule(definingModule: ModuleScript)
	DefiningModules[definingModule] = nil
	CollectedByModule[definingModule] = nil
	DirtyDefiningModules[definingModule] = nil
	for targetModule, defs in TargetToDefinitions do
		defs[definingModule] = nil
		if next(defs) == nil then
			TargetToDefinitions[targetModule] = nil
		end
	end
end

SetCalls = function(callingModule: ModuleScript, calls: { [string]: any })
	if not callingModule or type(calls) ~= "table" then return end

	AllCallsByCallingModule[callingModule] = calls

	for definingModule in CollectedByModule do
		if definingModule.Parent then
			MarkDirty(definingModule)
		end
	end
end

ClearCalls = function(callingModule: ModuleScript)
	if not callingModule then return end

	AllCallsByCallingModule[callingModule] = nil

	for definingModule in CollectedByModule do
		if definingModule.Parent then
			MarkDirty(definingModule)
		end
	end
end

local CollectedDecorators = setmetatable({}, {
	__index = function(_, definingModule)
		if typeof(definingModule) == "Instance" and definingModule:IsA("ModuleScript") then
			return GetCollected(definingModule)
		end
		return nil
	end,
	__iter = function()
		local all = {}
		for defMod in CollectedByModule do
			all[defMod] = GetCollected(defMod)
		end
		return next, all, nil
	end
})

local metaHandlers = {
	["export"] = function(parser, name, args)
		if not args or #args == 0 then return end

		local activeExtractors = {}
		for _, exportType in args do
			if type(exportType) ~= "string" then continue end
			local baseName, option = exportType:match("^([^:]+):?(.*)$")
			if option == "" then option = nil end

			local extractor = exports[baseName]
			if extractor then
				table.insert(activeExtractors, { name = baseName, func = extractor, option = option })
			end
		end

		if #activeExtractors > 0 then
			parser.dynamicDecorators[name] = parser.dynamicDecorators[name] or {}
			parser.dynamicDecorators[name].activeExtractors = activeExtractors
		end
	end,
	["context"] = function(parser, name, args)
		if not args or #args == 0 then return end
		parser.dynamicDecorators[name] = parser.dynamicDecorators[name] or {}
		parser.dynamicDecorators[name].crossContexts = args
	end,
	["collect"] = function(parser, name, args)
		local definingModule = parser.module
		if not definingModule then return end

		DefiningModules[definingModule] = true

		parser.dynamicDecorators[name] = parser.dynamicDecorators[name] or {}
		parser.dynamicDecorators[name].definingModule = definingModule
	end,
}

local function IsTargetModule(targetModule: ModuleScript): boolean
	return TargetToDefinitions[targetModule] ~= nil
end

local RegisterDecorator = {
	dynamicDecorators = {},
	CollectedDecorators = CollectedDecorators,
	GetCollected = GetCollected,
	GetAggregatedCalls = GetAggregatedCalls,
	SetCalls = SetCalls,
	ClearCalls = ClearCalls,
	ClearTarget = ClearTarget,
	ClearDefiningModule = ClearDefiningModule,
	SyncPayload = SyncPayload,
	MarkDirty = MarkDirty,
	FlushDirty = FlushDirty,
	IsTargetModule = IsTargetModule,
	DefiningModules = DefiningModules,
	AddService = AddService,
	AddModule = AddModule,
}

function RegisterDecorator.Init(self, parser)
	parser:OnCall("game:RegisterDecorator", function(args, line: number)
		local name = args[1]
		if not name then return end

		local funcStr = args[2]
		local decoratorArgs = {}
		local argsAutocomplete = {}

		local prototype = nil
		local signatureAst = nil
		local docText, meta = parser:GetDocBeforeLine(line)

		local exportCount = 0
		for _, m in meta do
			if m.type == "export" and m.args then
				for _, exportType in m.args do
					if type(exportType) == "string" then
						exportCount += 1
					end
				end
			end
		end

		local hasParameters = false
		if funcStr and type(funcStr) == "string" then
			prototype = TypeParser.ExtractPrototype(funcStr)
			signatureAst = TypeParser.ParseSignature(prototype)

			if signatureAst and signatureAst.arguments and #signatureAst.arguments > 2 + exportCount then
				hasParameters = true
				for index = 3 + exportCount, #signatureAst.arguments do
					local argument = signatureAst.arguments[index]

					local typeStr = argument.type.value or argument.type.name or "any"
					local isOpt = argument.type.kind == "optional"
					if isOpt then typeStr = argument.type.inner.value or argument.type.inner.name or "any" end

					decoratorArgs[#decoratorArgs + 1] = `<{argument.name}{argument.name == "..." and "" or ": "}{typeStr}{isOpt and "?" or ""}>`

					local possibilities = {}
					local typeNode = isOpt and argument.type.inner or argument.type

					if typeNode.kind == "literal" and type(typeNode.value) == "string" then
						table.insert(possibilities, typeNode.value)
					elseif typeNode.kind == "reference" and typeNode.name == "boolean" then
						table.insert(possibilities, "true")
						table.insert(possibilities, "false")
					elseif typeNode.kind == "union" and (typeNode.elements or typeNode.types) then
						for _, elem in (typeNode.elements or typeNode.types) do
							if elem.kind == "literal" and type(elem.value) == "string" then
								table.insert(possibilities, elem.value)
							elseif elem.kind == "reference" and elem.name == "boolean" then
								table.insert(possibilities, "true")
								table.insert(possibilities, "false")
							end
						end
					end

					if #possibilities > 0 then
						argsAutocomplete[index - 2 - exportCount] = possibilities
					end
				end
			end
		end

		local injectedParameters = {}
		if signatureAst and signatureAst.arguments and signatureAst.arguments[2] then
			local funcArg = signatureAst.arguments[2]
			if funcArg.type and funcArg.type.kind == "function" and funcArg.type.arguments then
				for _, param in funcArg.type.arguments do
					local isOpt = param.optional == true or (param.type and param.type.kind == "optional")
					local isVar = param.isVariadic == true or param.name == "..." or (param.type and (param.type.kind == "variadic" or (param.type.inner and param.type.inner.kind == "variadic")))
					local typeName = nil
					local rawType = param.type
					if isOpt and rawType and rawType.kind == "optional" then
						rawType = rawType.inner
					end
					if rawType then
						typeName = rawType.name or (rawType.path and table.concat(rawType.path, ".")) or rawType.value
					end

					-- Skip generic variadics (...any, ...any?) which are just wrapper signatures
					local isGenericVar = isVar and (typeName == "any" or typeName == "any?" or typeName == nil)
					if not isGenericVar then
						table.insert(injectedParameters, {
							name = param.name,
							type = typeName or "any",
							typeNode = param.type,
							optional = isOpt,
							isVariadic = isVar,
							definingModule = parser.module,
						})
					end
				end
			end
		end

		local hasRealInjected = false
		for _, param in injectedParameters do
			local isGenericVar = (param.isVariadic or param.name == "..." or param.name == nil)
				and (param.type == "any" or param.type == "any?" or param.type == nil)
			if not isGenericVar then
				hasRealInjected = true
				break
			end
		end
		if not hasRealInjected then
			injectedParameters = {}
		end

		local argSuffix = #decoratorArgs > 0 and " " .. table.concat(decoratorArgs, " ") or ""
		local fullLabel = "@" .. name .. argSuffix

		for _, m in meta do
			local tagHandler = metaHandlers[m.type]
			if tagHandler then
				tagHandler(parser, name, m.args)
			end
		end

		parser.dynamicDecorators[name] = parser.dynamicDecorators[name] or {}
		local decData = parser.dynamicDecorators[name]
		decData.injectedParameters = #injectedParameters > 0 and injectedParameters or nil
		RegisterDecorator.dynamicDecorators[name] = decData

		decData.apply = function(item, ancestor, ...)
			local rawArgs = {...}
			local regularArgs = {}
			local nestedNodes = {}

			for _, arg in rawArgs do
				if type(arg) == "table" and type(arg.type) == "string" and arg.args ~= nil then
					table.insert(nestedNodes, arg)
				else
					table.insert(regularArgs, arg)
				end
			end

			if #regularArgs == 0 then
				table.insert(regularArgs, true)
			end

			if not hasParameters and regularArgs[1] == false then return end

			local exportData = {}
			local exportsMap = {}

			if decData.activeExtractors then
				for _, extractorData in decData.activeExtractors do
					local data = extractorData.func(item, extractorData.option, table.unpack(regularArgs))
					if data ~= nil then
						table.insert(exportData, data)
						exportsMap[extractorData.name] = data
					end
				end
			end

			for _, arg in regularArgs do
				table.insert(exportData, arg)
			end

			local nestedMetadata
			local effectiveParser = item.parser or parser
			if #nestedNodes > 0 and effectiveParser and effectiveParser.ApplyNestedDecorators then
				nestedMetadata = effectiveParser:ApplyNestedDecorators(item, nestedNodes)
			elseif #nestedNodes > 0 then
				nestedMetadata = {}
				for _, node in nestedNodes do
					table.insert(nestedMetadata, { node.type, node.args or {} })
				end
			end

			if nestedMetadata and #nestedMetadata > 0 then
				exportsMap.nested = nestedMetadata
			end

			if ancestor then
				if nestedMetadata and #nestedMetadata > 0 then
					table.insert(ancestor, {
						name,
						exportData,
						nestedMetadata,
					})
				else
					table.insert(ancestor, {
						name,
						exportData,
					})
				end
			end

			if decData.definingModule then
				if not item.discovery or item.discovery.type ~= "indexing" then return end

				local targetModule = item.discovery and item.discovery.module or (item.parser and item.parser.module)
				if not targetModule or typeof(targetModule) ~= "Instance" or not targetModule:IsA("ModuleScript") then return end
				local targetModuleName = targetModule.Name
				local modules = {}
				if targetModuleName and not table.find(modules, targetModuleName) then
					table.insert(modules, targetModuleName)
				end
				local itemTable = item.table or item.tableName
				if itemTable and not table.find(modules, itemTable) then
					table.insert(modules, itemTable)
				end
				if ModulesByModule[targetModule] then
					for modName in ModulesByModule[targetModule] do
						if not table.find(modules, modName) then
							table.insert(modules, modName)
						end
					end
				end
				if item.parser and item.parser.tables then
					for _, tbl in item.parser.tables do
						if tbl.__modules then
							for _, mod in tbl.__modules do
								if type(mod.name) == "string" and not table.find(modules, mod.name) then
									table.insert(modules, mod.name)
								end
							end
						end
					end
				end

				local methodType = "."
				if item.methodes and table.find(item.methodes, ":") then
					methodType = ":"
				end

				local services = {}
				if ServicesByModule[targetModule] then
					for srvName in ServicesByModule[targetModule] do
						if not table.find(services, srvName) then
							table.insert(services, srvName)
						end
					end
				end
				if item.parser and item.parser.tables then
					for _, tbl in item.parser.tables do
						if tbl.__services then
							for _, srv in tbl.__services do
								if type(srv.name) == "string" and not table.find(services, srv.name) then
									table.insert(services, srv.name)
								end
							end
						end
					end
				end

				-- Entry structure:
				-- [1] modules list (e.g. ["ClientTests"])
				-- [2] services list (e.g. ["Service1"] or [])
				-- [3] methodName (e.g. "Init")
				-- [4] methodType ("." or ":")
				-- [5] exportsMap (dictionary of { [extractorName] = data, nested = nestedMetadata })
				-- [6+] decorator arguments (e.g. true)
				local entry = {
					modules,
					services,
					item.name,
					methodType,
					exportsMap,
				}
				for _, arg in regularArgs do
					table.insert(entry, arg)
				end

				local definingModule = decData.definingModule
				CollectedByModule[definingModule] = CollectedByModule[definingModule] or {}
				CollectedByModule[definingModule][name] = CollectedByModule[definingModule][name] or {}
				CollectedByModule[definingModule][name][targetModule] = CollectedByModule[definingModule][name][targetModule] or {}
				CollectedByModule[definingModule][name][targetModule][item.name] = entry

				TargetToDefinitions[targetModule] = TargetToDefinitions[targetModule] or {}
				TargetToDefinitions[targetModule][definingModule] = true

				MarkDirty(definingModule)
			end
		end

		local decCompItem = parser:CreateCompletionItem({
			name = name,
			label = "@"..name,
			type = "decorator",
			kind = (pcall(function() return Enum.CompletionItemKind.Event end) and Enum.CompletionItemKind.Event) or nil,
			detail = fullLabel,
			prototype = prototype,
			documentation = docText,
			decorators = meta,
			args = next(argsAutocomplete) and argsAutocomplete or nil,
			injectedParameters = #injectedParameters > 0 and injectedParameters or nil,
		})
		parser.tables.__decorators = parser.tables.__decorators or {}
		parser.tables.__decorators[name] = decCompItem
		RegisterDecorator.dynamicDecorators[name] = decCompItem
	end)
end

setmetatable(RegisterDecorator, {
	__call = function(self, parser)
		self:Init(parser)
	end
})

return RegisterDecorator