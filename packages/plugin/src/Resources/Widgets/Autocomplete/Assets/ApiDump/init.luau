--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// types //--
type array = {[number]: any}
type dict = {[any]: any}

local HttpService = game:GetService("HttpService")
local apiWebService = "https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json"

local ApiDump = {}

ApiDump.RootClassName = "<<<ROOT>>>"
ApiDump.CachedApiDump = nil :: dict

-- Rebatir la table de completion d'une classe coutait 166 a 321 us, et le dump ne bouge plus une
-- fois telecharge. Batie une fois, rendue en copie plate : ce qui la recoit y ecrit des cles.
-- Declaree ici et pas plus bas : FetchApiDump la vide, et une locale declaree apres la fonction
-- qui l'utilise est lue comme un global nil.
local autoCompletionCache: dict = {}

--// Private //--
local function warp<Function>(func: Function, ...: any): () -> Function
	local args = {...}

	return function()
		return func(func, table.unpack(args))
	end
end

--// Public //--

--[=[
	Downloads and caches a fresh copy of the API dump.
]=]
function ApiDump:FetchApiDump(): (boolean, string?)
	local success, result = pcall(function()
		return HttpService:GetAsync(apiWebService)
	end)

	if not success then
		return false, result
	end

	success, result = pcall(function()
		ApiDump.CachedApiDump = HttpService:JSONDecode(result)
	end)

	if not success then
		return false, result
	end

	for _, module: ModuleScript? in script:GetDescendants() do
		if not module:IsA("ModuleScript") then continue end

		local element = require(module)
		table.insert(ApiDump.CachedApiDump.Classes, element)
	end

	table.clear(autoCompletionCache)

	return true
end

--[=[
	Returns a list of class entries tagged with the given tag (e.g. "Service", "NotCreatable", etc.).
]=]
local taggedCache: { [string]: { dict } } = {}
function ApiDump:GetTagged(tag: string): { dict }
	if taggedCache[tag] then return taggedCache[tag] end

	if not ApiDump.CachedApiDump then
		ApiDump:FetchApiDump()
	end

	local dump = ApiDump.CachedApiDump
	if not dump or not dump.Classes then
		return {}
	end

	local tagged = {}
	for _, entry in dump.Classes do
		if entry.Tags and table.find(entry.Tags, tag) then
			table.insert(tagged, entry)
		end
	end

	taggedCache[tag] = tagged
	return tagged
end

--[=[
	Returns the class API entry for the given class name.
]=]
local classEntryCache: dict = {}
function ApiDump:GetClassEntry(className: string): dict
	if classEntryCache[className] then return classEntryCache[className] end

	-- Le dump vient d'un GetAsync. Sans reseau, avec HttpService coupe, ou si le service ne
	-- repond pas, CachedApiDump reste nil et cette ligne levait "attempt to index nil with
	-- 'Classes'" -- une erreur par module analyse, en plein milieu de l'indexation.
	local dump = ApiDump.CachedApiDump

	if not dump or not dump.Classes then
		return nil
	end

	for _, entry in dump.Classes do
		if entry.Name == className then
			classEntryCache[className] = entry
			return entry
		end
	end
end

--[=[
	Returns the subclass names for the given class name.
]=]
local subclassesCache: dict = {}
function ApiDump:GetSubclasses(className: string): dict
	if subclassesCache[className] then return subclassesCache[className] end

	local dump = ApiDump.CachedApiDump

	if not dump or not dump.Classes then
		return {}
	end

	local subclasses = {}
	for _, entry in pairs(dump.Classes) do
		if entry.Superclass == className then
			subclasses[#subclasses + 1] = entry
		end
	end

	subclassesCache[className] = subclasses
	return subclasses
end

--[=[
	Returns a list of member entries belonging to the given class name or its superclasses.
]=]
local membersCache: dict = {}
function ApiDump:GetMembers(className: string): dict
	if membersCache[className] then return membersCache[className] end

	local members: dict = {}
	local entries: array = {}

	do
		local currentEntry = ApiDump:GetClassEntry(className)

		while currentEntry and currentEntry.Superclass ~= ApiDump.RootClassName do
			table.insert(entries, 1, currentEntry)
			currentEntry = ApiDump:GetClassEntry(currentEntry.Superclass)
		end

		if currentEntry == nil then
			--error("Class name " .. className .. " could not be found")
		end

		table.insert(entries, 1, currentEntry)
	end

	for _, entry: dict in entries do
		for _, member: dict in entry.Members do
			members[#members + 1] = member
		end
	end

	membersCache[className] = members
	return members
end

--[=[
	Returns autocompletion dict based on member.
]=]
local SpecialTypes = {
	["null"] = "()",

	["int"] = "number",
	["bool"] = "boolean",
	["float"] = "number",

	["Array"] = "{ any }",
	["Dictionary"] = "{ [any]: any }",

	["Instances"] = "{ Instance }",

	["Tuple"] = "...any",
	["Function"] = "(...any) -> (...any)"
}

local SelfReturningMethods = {
	["Clone"] = true,
}

local function FormatFunctions(member: dict, className: string?): (string, string)
	local parameters = {}

	if member.Parameters then
		for _, parameter in member.Parameters do
			local parameter_type = ""
			if parameter.Type and parameter.Type.Name then
				parameter_type = SpecialTypes[parameter.Type.Name] or parameter.Type.Name
			end

			table.insert(parameters, parameter.Name .. (parameter_type and (": "..parameter_type) or ""))
		end
	end

	local function_type = "()"
	if member.ReturnType and member.ReturnType.Name then
		function_type = SpecialTypes[member.ReturnType.Name] or member.ReturnType.Name
	end

	if SelfReturningMethods[member.Name] and className then
		function_type = className
	end

	return member.Name .. "("..table.concat(parameters, ", ").."): " .. function_type, function_type
end

local MemberTypes = {
	["Property"] = {
		Methode = {"."},
		Kind = Enum.CompletionItemKind.Property
	},
	["Function"] = {
		Methode = {":"},
		Kind = Enum.CompletionItemKind.Function,
		Format = FormatFunctions
	},
	["Event"] = {
		Methode = {"."},
		Kind = Enum.CompletionItemKind.Event,
		Format = function() return "RBXScriptSignal", "RBXScriptSignal" end
	},
	["Callback"] = {
		Methode = {"."},
		Kind = Enum.CompletionItemKind.Function,
		Tags = {},
		Format = FormatFunctions
	}
}

function ApiDump:MemberToCompletion(member: dict, className: string): (string, dict)
	local CompletionItem = {
		completion = {}
	}

	local memberType = MemberTypes[member.MemberType]

	CompletionItem.methodes = memberType.Methode or "."

	CompletionItem.completion.kind = memberType.Kind or Enum.CompletionItemKind.Text

	if member.ValueType and member.ValueType.Category then
		if member.ValueType.Category == "DataType" then
			CompletionItem.completion.kind = Enum.CompletionItemKind:FromName(member.ValueType.Name) or CompletionItem.completion.kind
		else
			CompletionItem.completion.kind = Enum.CompletionItemKind:FromName(member.ValueType.Category) or CompletionItem.completion.kind
		end
	end

	local member_type, completion_type = "", ""
	if memberType.Format then
		member_type, completion_type = memberType.Format(member, className)
	elseif member.ValueType and member.ValueType.Name then
		member_type = SpecialTypes[member.ValueType.Name] or member.ValueType.Name
		completion_type = member_type
	end

	CompletionItem.completion.tags = memberType.Tags and table.clone(memberType.Tags) or {}
	if member.Tags then
		if table.find(member.Tags, "Deprecated") then
			CompletionItem.completion.tags[Enum.CompletionItemTag.Deprecated] = true
		end
	end

	CompletionItem.completion.detail = member_type
	CompletionItem.completion.learnMoreLink = "https://create.roblox.com/docs/reference/engine/classes/"..(className or member.Name)..(className and ("#"..member.Name)) or nil

	CompletionItem.next = warp(ApiDump.GetAutoCompletion, completion_type)

	return member.Name, CompletionItem
end

--[=[
	Returns autocompletion dict based on members of a class.
]=]
function ApiDump:GetAutoCompletion(className: string): dict?
	local cached = autoCompletionCache[className]
	if cached then return table.clone(cached) end

	local members = ApiDump:GetMembers(className)
	if not members then return end

	local completions = {}
	for _, member: dict in members do
		local key, completion = ApiDump:MemberToCompletion(member, className)
		completions[key] = completion
	end

	autoCompletionCache[className] = completions

	return table.clone(completions)
end

return ApiDump