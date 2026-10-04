--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Resources = script.Parent.Parent.Parent.Parent.Parent
local MetadataUtils = require(Resources.Modules.MetadataUtils)

local ExtendCall = {}

type Definition = {
	methodName: string,
	tableName: string,
	definingModule: ModuleScript?,
	itemArg: number,
	itemType: string?,
	childArg: number?,
	childType: string?,
}

type CallRecord = {
	receiver: string,
	method: string,
	args: { any },
	childKeys: { string }?,
	line: number,
	depth: number,
}

-- Registry of definitions per defining module
local DefinitionsByModule: { [ModuleScript]: { [string]: Definition } } = {}

-- Fast lookup by method name
local DefinitionsByMethod: { [string]: { Definition } } = {}

-- Table member definitions per class name (e.g. "EnumClass", "EnumItemClass")
local ClassMembers: { [string]: { [string]: any } } = {}
local ClassMembersByModule: { [ModuleScript]: { string } } = {}

-- Calls recorded per module
local CallsByModule: { [ModuleScript]: { CallRecord } } = {}

-- Tracked method names to optimize line scanning (populated dynamically from @extend docstrings)
local TrackedMethods: { [string]: boolean } = {}

--[=[
    Safely extracts string identifiers and keys from a table literal string.
    Splits entries by top-level commas and parses keys to guarantee zero false positives from values.

    @param tableStr The string representing the table literal (e.g. '{ "Fire", "Ice" }').
    @param parser Optional Parser instance to leverage SplitArguments.
    @return A list of unique member names extracted from the table.
]=]
local function parseTableLiteral(tableStr: string, parser: any?): { string }
	local items: { string } = {}
	if not string.find(tableStr, "{", 1, true) then return items end

	local inside = string.match(tableStr, "^%s*{(.*)}%s*$")
	if not inside or inside == "" then return items end

	-- Split entries by top-level commas
	local rawEntries: { any }
	if parser and parser.SplitArguments then
		rawEntries = parser:SplitArguments(inside)
	else
		rawEntries = {}
		local depth = 0
		local inQuote = false
		local quoteChar = nil
		local startIdx = 1
		for idx = 1, #inside do
			local c = inside:sub(idx, idx)
			if not inQuote then
				if c == '"' or c == "'" or c == "`" then
					inQuote = true
					quoteChar = c
				elseif c == "(" or c == "{" or c == "[" then
					depth += 1
				elseif c == ")" or c == "}" or c == "]" then
					depth -= 1
				elseif c == "," and depth == 0 then
					table.insert(rawEntries, inside:sub(startIdx, idx - 1))
					startIdx = idx + 1
				end
			elseif c == quoteChar and inside:sub(idx - 1, idx - 1) ~= "\\" then
				inQuote = false
			end
		end
		if startIdx <= #inside then
			table.insert(rawEntries, inside:sub(startIdx))
		end
	end

	for _, entry in rawEntries do
		local strEntry = string.match(tostring(entry), "^%s*(.-)%s*$") or ""
		if strEntry == "" then continue end

		-- 1. Bracket assignment: ["key"] = ... or ['key'] = ...
		local bracketKey = string.match(strEntry, "^%[%s*[\"'](.-)[\"']%s*%]%s*=")
		if bracketKey then
			if not table.find(items, bracketKey) then
				table.insert(items, bracketKey)
			end
			continue
		end

		-- 2. Identifier assignment: key = ...
		local identKey = string.match(strEntry, "^([%w_]+)%s*=")
		if identKey then
			if not table.find(items, identKey) then
				table.insert(items, identKey)
			end
			continue
		end

		-- 3. Quoted string: "Fire", 'Ice', `Lightning` (supports spaces like "Fire Ball")
		local quoted = string.match(strEntry, "^[\"'](.-)[\"']$") or string.match(strEntry, "^`(.-)`$")
		if quoted then
			if not table.find(items, quoted) then
				table.insert(items, quoted)
			end
			continue
		end

		-- 4. Direct unquoted string from parser:SplitArguments
		if type(entry) == "string" and not string.find(strEntry, "[%s=]") then
			if not table.find(items, entry) then
				table.insert(items, entry)
			end
		end
	end

	return items
end

--[=[
    Calculates parenthesis balance depth across text lines.

    @param text The text segment to analyze.
    @param depth The initial depth counter.
    @return The updated depth counter.
]=]
local function parenDepth(text: string, depth: number): number
	for c in string.gmatch(text, "[%(%)]") do
		depth += c == "(" and 1 or -1
		if depth <= 0 then
			return 0
		end
	end
	return depth
end

--[=[
    Rebuilds the fast method lookup index from all registered module definitions.
]=]
local function rebuildMethodIndex(): ()
	table.clear(DefinitionsByMethod)
	TrackedMethods = {}

	for _, moduleDefs in DefinitionsByModule do
		for methodName, def in moduleDefs do
			DefinitionsByMethod[methodName] = DefinitionsByMethod[methodName] or {}
			table.insert(DefinitionsByMethod[methodName], def)
			TrackedMethods[methodName] = true
		end
	end
end

--[=[
    Registers a function definition marked with the @extend decorator.
    Maintains clean de-duplication across re-indexes.

    @param definingModule The ModuleScript declaring the function.
    @param tableName The name of the table or class the method belongs to.
    @param methodName The identifier name of the method.
    @param meta The extension metadata parameters.
]=]
function ExtendCall.RegisterDefinition(
	definingModule: ModuleScript?,
	tableName: string,
	methodName: string,
	meta: { itemArg: number?, itemType: string?, childArg: number?, childType: string? }
): ()
	local def: Definition = {
		methodName = methodName,
		tableName = tableName,
		definingModule = definingModule,
		itemArg = meta.itemArg or 1,
		itemType = meta.itemType,
		childArg = meta.childArg,
		childType = meta.childType,
	}

	if definingModule then
		DefinitionsByModule[definingModule] = DefinitionsByModule[definingModule] or {}
		DefinitionsByModule[definingModule][methodName] = def
	end

	local list = DefinitionsByMethod[methodName]
	if list then
		local replaced = false
		for idx, existing in list do
			if existing.definingModule == definingModule and existing.tableName == tableName then
				list[idx] = def
				replaced = true
				break
			end
		end
		if not replaced then
			table.insert(list, def)
		end
	else
		DefinitionsByMethod[methodName] = { def }
	end

	TrackedMethods[methodName] = true
end

--[=[
    Clears all cached calls, class members, and definitions associated with a specific ModuleScript.
    Ensures zero memory leaks when scripts are modified or deleted.

    @param moduleScript The ModuleScript being cleared.
]=]
function ExtendCall.ClearModule(moduleScript: ModuleScript): ()
	CallsByModule[moduleScript] = nil

	if DefinitionsByModule[moduleScript] then
		DefinitionsByModule[moduleScript] = nil
		rebuildMethodIndex()
	end

	local trackedClasses = ClassMembersByModule[moduleScript]
	if trackedClasses then
		for _, className in trackedClasses do
			ClassMembers[className] = nil
		end
		ClassMembersByModule[moduleScript] = nil
	end
end

--[=[
    Initializes the analyzer for a parser pass.

    @param parser The current Parser instance.
]=]
function ExtendCall:Init(parser: any): ()
	if parser.module then
		CallsByModule[parser.module] = {}
	end
end

--[=[
    Runs the analyzer on the completed parser state.
    Discovers definitions, saves class members, and scans call expressions in a single pass.

    @param parser The current Parser instance.
]=]
function ExtendCall:Run(parser: any): ()
	-- Phase 1: Discover class members and @extend definitions in parser.tables
	if type(parser.tables) == "table" then
		local recordedClasses: { string }? = nil
		if parser.module then
			recordedClasses = {}
			ClassMembersByModule[parser.module] = recordedClasses
		end

		for tableName, tbl in parser.tables do
			if type(tbl) ~= "table" then continue end

			ClassMembers[tableName] = ClassMembers[tableName] or {}
			if recordedClasses then
				table.insert(recordedClasses, tableName)
			end

			for fieldName, fieldItem in tbl do
				if type(fieldItem) ~= "table" then
					continue
				end

				if type(fieldName) == "string" and string.sub(fieldName, 1, 2) ~= "__" then
					ClassMembers[tableName][fieldName] = fieldItem
				end

				local extendMeta = fieldItem.extend
				if not extendMeta and type(fieldItem.metadata) == "table" then
					local metaArgs = MetadataUtils.get(fieldItem.metadata, "extend")
					if metaArgs and type(metaArgs) == "table" then
						extendMeta = {
							itemArg = metaArgs[1] or 1,
							itemType = metaArgs[2],
							childArg = metaArgs[3],
							childType = metaArgs[4],
						}
					end
				end

				if extendMeta and type(extendMeta) == "table" then
					local methodName = fieldItem.name or fieldName
					ExtendCall.RegisterDefinition(parser.module, tableName, methodName, extendMeta)
				end
			end
		end
	end

	-- Phase 2: Track variable aliases and scan calls in a single pass over lines
	local varAliases: { [string]: string } = {}

	-- Inherit services, modules, and builtins already resolved by ParsingHandler
	if type(parser.tables) == "table" then
		for tblName, tblData in parser.tables do
			if type(tblData) == "table" then
				if tblData.__builtin and type(tblData.__builtin) == "table" and tblData.__builtin.name then
					varAliases[tblName] = tblData.__builtin.name
				elseif tblData.__services and type(tblData.__services) == "table" and #tblData.__services > 0 and type(tblData.__services[1]) == "table" and tblData.__services[1].name then
					varAliases[tblName] = tblData.__services[1].name
				elseif tblData.__modules and type(tblData.__modules) == "table" and #tblData.__modules > 0 and type(tblData.__modules[1]) == "table" and tblData.__modules[1].name then
					varAliases[tblName] = tblData.__modules[1].name
				end
			end
		end
	end

	local moduleCalls = parser.module and CallsByModule[parser.module] or {}
	local i = 1
	local lineCount = #parser.lines

	while i <= lineCount do
		local line = parser.lines[i]

		-- Quick check 1: track direct local variable aliases (e.g. local E = Enum)
		local aliasVar, targetVar = string.match(line, "^%s*local%s+([%w_]+)%s*=%s*([%w_]+)%s*$")
		if aliasVar and targetVar and targetVar ~= "nil" then
			varAliases[aliasVar] = varAliases[targetVar] or targetVar
			i += 1
			continue
		end

		-- Quick check 2: lines without parentheses or comments cannot be calls
		if not string.find(line, "(", 1, true) or string.match(line, "^%s*%-%-") then
			i += 1
			continue
		end

		-- Match receiver.method( or receiver:method(
		local receiverStr, sep, methodFound = string.match(line, "([%w_%.]+)%s*([:%.])%s*([%w_]+)%s*%(")
		if not (receiverStr and methodFound) then
			i += 1
			continue
		end

		-- Check if receiver is a known alias/table or if method is in TrackedMethods
		local firstDot = string.find(receiverStr, "%.")
		local rootVar = firstDot and string.sub(receiverStr, 1, firstDot - 1) or receiverStr
		local remainder = firstDot and string.sub(receiverStr, firstDot) or ""

		local isKnownReceiver = varAliases[rootVar] ~= nil or (parser.tables and parser.tables[rootVar] ~= nil)
		local isTrackedMethod = TrackedMethods[methodFound] == true

		if not (isKnownReceiver or isTrackedMethod) then
			i += 1
			continue
		end

		local parenPos = string.find(line, "%(")
		if parenPos then
			-- Fast single-line balanced match, fallback to multi-line accumulation
			local argStr = line:sub(parenPos):match("^%b()")
			if not argStr then
				local parts = { line }
				local k = i + 1
				local depth = parenDepth(string.sub(line, parenPos), 0)

				while k <= lineCount and depth > 0 do
					parts[#parts + 1] = parser.lines[k]
					depth = parenDepth(parser.lines[k], depth)
					k += 1
				end

				if depth == 0 then
					local fullCallText = table.concat(parts, "\n")
					argStr = fullCallText:sub(parenPos):match("^%b()")
				end
			end

			if argStr then
				local args = parser:SplitArguments(argStr:sub(2, -2))

				-- Resolve receiver alias if present
				local resolvedReceiver = receiverStr
				if varAliases[rootVar] then
					resolvedReceiver = varAliases[rootVar] .. remainder
				end

				local childKeys = nil
				for a = 1, #args do
					local val = args[a]
					if type(val) == "string" and string.sub(val, 1, 1) == "{" and string.sub(val, -1, -1) == "}" then
						childKeys = parseTableLiteral(val, parser)
						break
					end
				end

				-- Pre-calculate receiver dot depth for fast O(1) integer sorting
				local depthCount = 0
				for _ in string.gmatch(resolvedReceiver, "%.") do
					depthCount += 1
				end

				table.insert(moduleCalls, {
					receiver = resolvedReceiver,
					method = methodFound,
					args = args,
					childKeys = childKeys,
					line = i,
					depth = depthCount,
				})
			end
		end

		i += 1
	end

	if parser.module then
		CallsByModule[parser.module] = moduleCalls
	end
end

--[=[
    Applies all recorded dynamic extensions onto the global autocompletion cache.
    Executed during RebuildDynamiqueTypes to guarantee order-independence and
    immutability of underlying base module caches.

    @param targetCache The global autocompletion cache dictionary.
]=]
function ExtendCall.ApplyExtensions(targetCache: { [string]: any }): ()
	if not next(CallsByModule) then
		return
	end

	-- Aggregate all calls from all indexed modules
	local allCalls: { CallRecord } = {}
	for _, calls in CallsByModule do
		for _, call in calls do
			table.insert(allCalls, call)
		end
	end

	if #allCalls == 0 then
		return
	end

	-- Sort calls by pre-computed receiver depth so parent namespaces are extended before child namespaces
	-- Pure integer comparison: 0 string allocations, 0 GC spikes
	table.sort(allCalls, function(a: CallRecord, b: CallRecord)
		return a.depth < b.depth
	end)

	for _, call in allCalls do
		-- Find matching definition for method
		local defs = DefinitionsByMethod[call.method]
		local def = defs and defs[1] or nil

		if not def then continue end

		-- Resolve target receiver node in targetCache
		local receiverSegments = string.split(call.receiver, ".")
		local currentTarget = targetCache[receiverSegments[1]]
		if type(currentTarget) ~= "table" then continue end

		-- Ensure currentTarget and its next table are safely cloned to protect ModuleTypesCaches
		if not currentTarget._clonedForExtend then
			currentTarget = table.clone(currentTarget)
			currentTarget.next = type(currentTarget.next) == "table" and table.clone(currentTarget.next) or {}
			currentTarget._clonedForExtend = true
			targetCache[receiverSegments[1]] = currentTarget
		end

		local valid = true
		for s = 2, #receiverSegments do
			local segName = receiverSegments[s]
			if type(currentTarget.next) == "table" and currentTarget.next[segName] then
				currentTarget = currentTarget.next[segName]
				if type(currentTarget) ~= "table" then
					valid = false
					break
				end
				if not currentTarget._clonedForExtend then
					currentTarget = table.clone(currentTarget)
					currentTarget.next = type(currentTarget.next) == "table" and table.clone(currentTarget.next) or {}
					currentTarget._clonedForExtend = true
				end
			else
				valid = false
				break
			end
		end

		if not valid or type(currentTarget.next) ~= "table" then continue end

		-- Extract item name from call arguments
		local itemArgIndex = def.itemArg or 1
		local itemName = call.args[itemArgIndex]
		if type(itemName) ~= "string" or itemName == "" then continue end

		local itemType = def.itemType

		-- Construct or reuse completion item for the registered member
		local itemEntry = currentTarget.next[itemName]
		if not itemEntry then
			itemEntry = {
				name = itemName,
				type = "variable",
				kind = Enum.CompletionItemKind.Class,
				detail = itemType,
				methodes = { "." },
				completion = {
					label = itemName,
					kind = Enum.CompletionItemKind.Class,
					detail = itemType,
					methodes = { "." },
				},
				next = {},
				_clonedForExtend = true,
			}
			currentTarget.next[itemName] = itemEntry
		elseif not itemEntry._clonedForExtend then
			itemEntry = table.clone(itemEntry)
			itemEntry.next = type(itemEntry.next) == "table" and table.clone(itemEntry.next) or {}
			itemEntry.methodes = { "." }
			if type(itemEntry.completion) == "table" then
				itemEntry.completion = table.clone(itemEntry.completion)
				itemEntry.completion.methodes = { "." }
			end
			itemEntry._clonedForExtend = true
			currentTarget.next[itemName] = itemEntry
		else
			itemEntry.methodes = { "." }
			if type(itemEntry.completion) == "table" then
				itemEntry.completion.methodes = { "." }
			end
		end

		-- Inherit methods and fields from itemType if available in ClassMembers or targetCache
		local parentClass = itemType and (ClassMembers[itemType] or (type(targetCache[itemType]) == "table" and targetCache[itemType].next)) or nil
		if type(parentClass) == "table" then
			for memberKey, memberVal in parentClass do
				if type(memberKey) == "string" and string.sub(memberKey, 1, 2) ~= "__" and not itemEntry.next[memberKey] then
					itemEntry.next[memberKey] = memberVal
				end
			end
		end

		-- Extract and populate child items
		local childKeys = call.childKeys
		if not childKeys then
			local childArgIndex = def.childArg
			local childArgValue = childArgIndex and call.args[childArgIndex] or nil

			if not childArgValue then
				for a = 1, #call.args do
					local val = call.args[a]
					if type(val) == "string" and string.sub(val, 1, 1) == "{" and string.sub(val, -1, -1) == "}" then
						childArgValue = val
						break
					end
				end
			end

			if type(childArgValue) == "string" then
				childKeys = parseTableLiteral(childArgValue)
			end
		end

		if childKeys then
			local childType = def.childType
			local childClass = childType and (ClassMembers[childType] or (type(targetCache[childType]) == "table" and targetCache[childType].next)) or nil

			for _, childKey in childKeys do
				local childEntry = itemEntry.next[childKey]
				if not childEntry then
					childEntry = {
						name = childKey,
						type = "variable",
						kind = Enum.CompletionItemKind.Class,
						detail = childType,
						methodes = { "." },
						completion = {
							label = childKey,
							kind = Enum.CompletionItemKind.Class,
							detail = childType,
							methodes = { "." },
						},
						next = {},
						_clonedForExtend = true,
					}
					itemEntry.next[childKey] = childEntry
				elseif not childEntry._clonedForExtend then
					childEntry = table.clone(childEntry)
					childEntry.next = type(childEntry.next) == "table" and table.clone(childEntry.next) or {}
					childEntry.methodes = { "." }
					if type(childEntry.completion) == "table" then
						childEntry.completion = table.clone(childEntry.completion)
						childEntry.completion.methodes = { "." }
					end
					childEntry._clonedForExtend = true
					itemEntry.next[childKey] = childEntry
				else
					childEntry.methodes = { "." }
					if type(childEntry.completion) == "table" then
						childEntry.completion.methodes = { "." }
					end
				end

				if type(childClass) == "table" then
					for memberKey, memberVal in childClass do
						if type(memberKey) == "string" and string.sub(memberKey, 1, 2) ~= "__" and not childEntry.next[memberKey] then
							childEntry.next[memberKey] = memberVal
						end
					end
				end
			end
		end
	end
end

return ExtendCall
