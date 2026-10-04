--!native
--!optimize 2

--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this framework requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Constants //--
local Assets = script.Parent

local ApiDump = require(Assets.ApiDump)
ApiDump:FetchApiDump()

local TypeParser = require(Assets.TypeParser)
local TypeResolver = require(Assets.TypeResolver)
local RegisterDecorator = require(Assets.Analyzers.RegisterDecorator)

local Decorators: { [string]: (...any) -> () } = {}
for _, module: ModuleScript in Assets.Decorators:GetChildren() do
	if not module:IsA("ModuleScript") then continue end
	Decorators[module.Name] = require(module)
end

local Analyzers = {}
for _, module: ModuleScript in Assets.Analyzers:GetChildren() do
	if not module:IsA("ModuleScript") then continue end
	table.insert(Analyzers, require(module))
end

--// Parser //--
local Parser = {}
Parser.__index = Parser

local ParsingHandler
local ModuleCache: { [ModuleScript]: { any } } = {}
local Dependencies: { [ModuleScript]: { [ModuleScript]: boolean } } = {}
local DynamicDecorators: { [ModuleScript]: { [string]: any } } = {}
local DecoratorNameToProvider: { [string]: ModuleScript } = {}

local DependencyGraph = require(Assets.DependencyGraph)
local MasterGraph = DependencyGraph.new()

local TrackedUsages = {}

export type MasterGraph = typeof(MasterGraph)
ParsingHandler = { MasterGraph = MasterGraph, TrackedUsages = TrackedUsages, ModuleCache = ModuleCache }

export type DependencyExtractor = {
	type: string,
	plain: string,
	pattern: string,
	resolve: (parser: any, match: string) -> ModuleScript?
}

-- `plain` est la tete litterale du motif : un `string.find` dessus avant de jouer le motif.
local DependencyExtractors: { DependencyExtractor } = {
	{
		type = "GetModule",
		plain = "game:GetModule",
		pattern = 'game:GetModule%s*%(%s*["\'`]([^"\'`]+)["\'`]%s*%)',
		resolve = function(parser, match) return parser:FindNodealModule(match) end
	},
	{
		type = "GetService",
		plain = "game:GetService",
		pattern = 'game:GetService%s*%(%s*["\'`]([^"\'`]+)["\'`]%s*%)',
		resolve = function(parser, match) return parser:FindNodealModule(match) end
	}
}

-- Les six mots qui ouvrent et ferment un scope, avec leur motif tout prepare.
local ScopeWords = {
	{ word = "function", step = 1 },
	{ word = "do", step = 1 },
	{ word = "then", step = 1 },
	{ word = "repeat", step = 1 },
	{ word = "end", step = -1 },
	{ word = "until", step = -1 },
}

for _, entry in ScopeWords do
	entry.pattern = "%f[%w]" .. entry.word .. "%f[%W]"
end

local AliasExtractors = {}
for _, ext in DependencyExtractors do
	local plain = string.match(ext.pattern, "^([%w_:]+)")
	if plain then
		table.insert(AliasExtractors, {
			plain = plain,
			pattern = "([%w_]+)%s*(:[^=]+)?=%s*" .. ext.pattern,
			extractor = ext
		})
	end
end

local function ClearCacheRecursively(module: ModuleScript, visited: { [ModuleScript]: boolean }?)
	local vis = visited or {}
	if vis[module] then return end
	vis[module] = true

	ModuleCache[module] = nil

	local deps = Dependencies[module]
	if deps then
		for dep in deps do
			ClearCacheRecursively(dep, vis)
		end
	end
end

local function ClearModuleDecorators(module: ModuleScript)
	local mods = DynamicDecorators[module]
	if mods then
		for decName in mods do
			if DecoratorNameToProvider[decName] == module then
				DecoratorNameToProvider[decName] = nil
			end
		end
	end
	DynamicDecorators[module] = nil
end

local SourceWatched: { [ModuleScript]: boolean } = setmetatable({}, { __mode = "k" })

-- Une seule invalidation par module : elle etait reposee a chaque analyse, donc un module cite
-- par vingt autres relancait vingt fois la meme purge a la premiere frappe.
local function watchSource(module: ModuleScript)
	if SourceWatched[module] then return end
	SourceWatched[module] = true

	module:GetPropertyChangedSignal("Source"):Connect(function()
		ClearCacheRecursively(module)
	end)
end

function Parser:AddDependency(dependency: ModuleScript, isStrict: boolean?, depType: string?)
	if not self.module then return end
	local deps = Dependencies[dependency]
	if not deps then
		deps = {}
		Dependencies[dependency] = deps
	end
	deps[self.module] = true

	MasterGraph:AddDependency(self.module, dependency, depType or "decorator", isStrict == nil and true or isStrict)
end

function Parser.new(source: string, module: ModuleScript?, context: string?, allowNonNodeal: boolean?)
	local self = setmetatable({}, Parser)

	self.source = source
	self.module = module
	if module then
		MasterGraph:GetNode(module)
		MasterGraph:ClearDependencies(module)
		if context == "indexing" then
			DynamicDecorators[module] = {}
		else
			DynamicDecorators[module] = DynamicDecorators[module] or {}
		end
		watchSource(module)
	end

	self.context = context
	self.allowNonNodeal = allowNonNodeal
	self.tables = {}
	self.analyzers = {}
	self.callHooks = {}
	self.types = {}
	self.exportedTypes = {}
	self.importedTypes = {}
	self.decorators = Decorators
	self.dynamicDecorators = module and DynamicDecorators[module] or {}
	self.trackedUsages = TrackedUsages

	self.source = source
	self.lines = string.split(source, "\n")

	return self
end

--// Index des modules par nom //--

-- Cette recherche balayait `game:GetDescendants()` en entier a chaque appel, et elle est
-- appelee une fois par reference a un module. Mesure sur ce depot : 50 788 descendants, et un
-- module de 700 lignes passait de 7 ms a 862 ms selon qu'il citait d'autres modules ou non.
-- L'analyse ne coutait presque rien ; c'etait ce balayage, repete des centaines de fois.
local ModuleByName: { [string]: ModuleScript } = {}
local NameWatched: { [ModuleScript]: boolean } = setmetatable({}, { __mode = "k" })
local CacheReady = false
local IndexDirty = false

local watchName

local function indexModuleNames()
	table.clear(ModuleByName)

	for _, desc in game:GetDescendants() do
		if desc:IsA("ModuleScript") then
			watchName(desc)

			if ModuleByName[desc.Name] == nil then
				ModuleByName[desc.Name] = desc
			end
		end
	end

	CacheReady = true
	IndexDirty = false
end

-- Un renommage ne se signale pas tout seul, et c'est la seule chose que l'index ne voyait pas.
watchName = function(desc: ModuleScript)
	if NameWatched[desc] then return end
	NameWatched[desc] = true

	desc:GetPropertyChangedSignal("Name"):Connect(function()
		for key, value in ModuleByName do
			if value == desc then
				ModuleByName[key] = nil
				IndexDirty = true
				break
			end
		end

		if ModuleByName[desc.Name] == nil then
			ModuleByName[desc.Name] = desc
		end
	end)
end

-- Tenu a jour au fil de l'eau plutot que reconstruit : un module ajoute ou retire se signale
-- lui-meme, donc l'index reste juste sans qu'on ait a rebalayer.
game.DescendantAdded:Connect(function(desc: Instance)
	if not CacheReady or not desc:IsA("ModuleScript") then return end

	watchName(desc)

	if ModuleByName[desc.Name] == nil then
		ModuleByName[desc.Name] = desc
	end
end)

-- Un homonyme masque redevient visible en partant : l'index ne le sait pas, d'ou le drapeau.
game.DescendantRemoving:Connect(function(desc: Instance)
	if CacheReady and desc:IsA("ModuleScript") and ModuleByName[desc.Name] == desc then
		ModuleByName[desc.Name] = nil
		IndexDirty = true
	end
end)

function Parser:FindNodealModule(name: string): ModuleScript?
	if not CacheReady then
		indexModuleNames()
	end

	local hit = ModuleByName[name]

	if hit and hit.Parent then
		return hit
	end

	-- Un nom absent n'est plus une raison de rebalayer : ajouts, retraits et renommages tiennent
	-- l'index a jour. `game:GetModule("Roun` en cours de frappe coutait 25 ms par caractere.
	if hit or IndexDirty then
		if hit then
			ModuleByName[name] = nil
		end

		indexModuleNames()

		hit = ModuleByName[name]

		if hit and hit.Parent then
			return hit
		end
	end

	return nil
end

--// Utilities //--
function Parser:ParseValue(val: string): any
	local trimmed = val:match("^%s*(.*%S)") or ""
	if trimmed == "" or trimmed == "true" then return true
	elseif trimmed == "false" then return false
	elseif trimmed == "nil" then return nil
	elseif tonumber(trimmed) then return tonumber(trimmed)
	else
		local first = trimmed:sub(1, 1)
		local last = trimmed:sub(-1, -1)
		if (first == '"' and last == '"') or (first == "'" and last == "'") or (first == "`" and last == "`") then
			return trimmed:sub(2, -2)
		end
		return trimmed
	end
end

function Parser:DedentLines(lines: { string }): string
	local minIndent = nil
	for _, line: string in lines do
		if line:match("%S") then
			local indent = line:match("^(%s*)")
			if not minIndent or #indent < minIndent then
				minIndent = #indent
			end
		end
	end
	minIndent = minIndent or 0

	local result = {}
	for _, line: string in lines do
		if #line >= minIndent then
			result[#result+1] = line:sub(minIndent+1)
		else
			result[#result+1] = ""
		end
	end
	return table.concat(result, "\n")
end


local CurrentlyParsing: { [ModuleScript]: boolean } = {}

-- S'arrete des que la profondeur retombe a zero : rejouer `%b()` sur une chaine qu'on rallonge la relit depuis le debut.
local function parenDepth(text: string, depth: number): number
	for c in string.gmatch(text, "[%(%)]") do
		depth += c == "(" and 1 or -1

		if depth <= 0 then
			return 0
		end
	end

	return depth
end

function Parser:ResolveModule(moduleScript: ModuleScript, isStrict: boolean?, depType: string?)
	if self.module then
		self:AddDependency(moduleScript, isStrict, depType)
	end

	if ModuleCache[moduleScript] then
		return table.unpack(ModuleCache[moduleScript])
	end

	if CurrentlyParsing[moduleScript] then
		return {}, {}, {}
	end

	CurrentlyParsing[moduleScript] = true

	local source = ""
	pcall(function()
		source = moduleScript.Source
	end)

	if source == "" then
		CurrentlyParsing[moduleScript] = nil
		return {}, {}, {}
	end

	watchSource(moduleScript)

	local returnedTable, allTables, exportedTypes = ParsingHandler(source, moduleScript, self.context, true)
	ModuleCache[moduleScript] = { returnedTable, allTables, exportedTypes }
	CurrentlyParsing[moduleScript] = nil
	return returnedTable, allTables, exportedTypes
end


function Parser:ExtractTypeDeclarations()
	self.types = {}
	self.exportedTypes = {}

	local i = 1
	while i <= #self.lines do
		local line = self.lines[i]
		local isExport, typeName = line:match("^%s*(export%s+)type%s+([%w_]+)%s*=")
		if not typeName then
			typeName = line:match("^%s*type%s+([%w_]+)%s*=")
		end
		if typeName then
			local fullDecl = line:match("=%s*(.*)") or ""

			local function isBalanced(str)
				local braces = 0
				local parens = 0
				local angles = 0
				local inString = false
				local stringChar = nil
				local escaped = false

				local idx = 1
				local len = #str
				while idx <= len do
					local c = str:sub(idx, idx)
					if not inString then
						if c == '"' or c == "'" or c == "`" then
							inString = true
							stringChar = c
						elseif c == "{" then
							braces += 1
						elseif c == "}" then
							braces -= 1
						elseif c == "(" then
							parens += 1
						elseif c == ")" then
							parens -= 1
						elseif c == "<" then
							angles += 1
						elseif c == ">" then
							angles -= 1
						end
					else
						if escaped then
							escaped = false
						elseif c == "\\" then
							escaped = true
						elseif c == stringChar then
							inString = false
						end
					end
					idx += 1
				end
				return braces <= 0 and parens <= 0 and angles <= 0
			end

			while i < #self.lines and not isBalanced(fullDecl) do
				i += 1
				fullDecl ..= " " .. self.lines[i]
			end

			local parsedType = TypeParser.Parse(fullDecl)
			self.types[typeName] = parsedType
			if isExport then
				self.exportedTypes[typeName] = parsedType
			end
		end
		i += 1
	end
end

function Parser:ResolveDecorator(decoratorType: string): any?
	local content = Decorators[decoratorType]

	if not content and self.dynamicDecorators and self.dynamicDecorators[decoratorType] then
		content = self.dynamicDecorators[decoratorType]
	end

	if not content then
		local provider = DecoratorNameToProvider[decoratorType]
		if provider and DynamicDecorators[provider] and DynamicDecorators[provider][decoratorType] then
			content = DynamicDecorators[provider][decoratorType]
			if self.module and self.module ~= provider then
				self:AddDependency(provider)
			end
		else
			for providerModule, mods in DynamicDecorators do
				if mods[decoratorType] then
					content = mods[decoratorType]

					if self.module and providerModule and self.module ~= providerModule then
						self:AddDependency(providerModule)
					end

					if providerModule then
						DecoratorNameToProvider[decoratorType] = providerModule
					end

					break
				end
			end
		end
	end

	return content
end

function Parser:ApplyNestedDecorators(item: any, nestedNodes: { any }): { any }
	local nestedMetadata = {}

	for _, childNode in nestedNodes do
		if type(childNode) ~= "table" or type(childNode.type) ~= "string" then continue end

		local childContent = self:ResolveDecorator(childNode.type)
		local childArgs = childNode.args or {}

		if childContent then
			if type(childContent.apply) == "function" then
				childContent.apply(item, nestedMetadata, table.unpack(childArgs))
			else
				table.insert(nestedMetadata, {
					childNode.type,
					childArgs
				})
			end
			if childContent.crossContexts then
				item.completion.crossContexts = item.completion.crossContexts or {}
				for _, ctx in childContent.crossContexts do
					table.insert(item.completion.crossContexts, ctx)
				end
			end
		else
			if self.tables then
				self.tables.__unresolved = self.tables.__unresolved or {}
				self.tables.__unresolved[childNode.type] = true
			end

			table.insert(nestedMetadata, {
				childNode.type,
				childArgs
			})
		end
	end

	return nestedMetadata
end

local function getVisualIndent(indentStr: string): number
	local visual = 0
	for i = 1, #indentStr do
		local byte = string.byte(indentStr, i)
		if byte == 9 then -- '\t'
			visual += 4 - (visual % 4)
		else
			visual += 1
		end
	end
	return visual
end

--// Factory //--
function Parser:CreateCompletionItem(config: any)
	local detail = config.detail or config.name
	local label = config.label or config.name

	local item = {
		name = config.name,
		table = config.table or config.tableName,
		type = config.type or "unknown",
		parser = self,

		discovery = {
			type = self.context,
			module = self.module
		},

		completion = {
			label = label,
			kind = config.kind or Enum.CompletionItemKind.Text,

			detail = detail,
			documentation = config.documentation or "",

			learnMoreLink = config.learnMoreLink,
			overloads = config.overloads,
			tags = config.tags or {},
			preselect = config.preselect,
			args = config.args,
		},

		decorators = config.decorators or {},
		metadata = config.metadata or {},

		cache = {}
	}

	-- Optional fields
	if config.prototype or config.type == "function" then
		item.prototype = config.prototype or detail
	end

	if config.methodes or config.type == "function" or config.type == "variable" then
		item.methodes = config.methodes or { "." }
	end

	if config.arguments then
		item.arguments = config.arguments
	end

	if config.injectedParameters then
		item.injectedParameters = config.injectedParameters
		item.completion.injectedParameters = config.injectedParameters
	end

	if config.next and next(config.next) then
		item.next = config.next
	end

	-- Apply decorators
	for _, decorator in item.decorators do
		local content = self:ResolveDecorator(decorator.type)

		if content then
			if type(content.apply) == "function" then
				content.apply(item, item.metadata, table.unpack(decorator.args))
			end
			if content.crossContexts then
				item.completion.crossContexts = item.completion.crossContexts or {}
				for _, ctx in content.crossContexts do
					table.insert(item.completion.crossContexts, ctx)
				end
			end
		else
			if type(decorator.type) == "string" then
				self.tables.__unresolved = self.tables.__unresolved or {}
				self.tables.__unresolved[decorator.type] = true

				table.insert(item.metadata, {
					decorator.type,
					decorator.args
				})
			end
		end
	end

	return item
end

--// Extractor //--
function Parser:ExtractDocAndMeta(block: string): (string, any)
	if not block or block == "" then return "", {} end

	local docLines = {}
	local stack = {}
	local meta = {}

	local function pushNode(typeName: string, indent: number)
		local node = { type = typeName, args = {} }
		stack[#stack+1] = { indent = indent, list = {}, current = node }
		return node
	end

	local function popStackTo(indent: number)
		while #stack > 0 and stack[#stack].indent >= indent do
			local top = table.remove(stack)
			if top.current.textBuffer then
				table.insert(top.current.args, self:DedentLines(top.current.textBuffer))
				top.current.textBuffer = nil
			end
			if #top.current.args == 0 then
				table.insert(top.current.args, true)
			end
			if #top.list > 0 then
				top.current.nested = top.list
				for _, subNode in top.list do
					table.insert(top.current.args, subNode)
				end
			end
			if #stack > 0 then
				table.insert(stack[#stack].list, top.current)
			else
				table.insert(meta, top.current)
			end
		end
	end

	for line in block:gmatch("[^\r\n]+") do
		local indent, trimmed = line:match("^(%s*)(.-)%s*$")
		local indentLen = getVisualIndent(indent)

		-- Strip docblock delimiters (--[=*[ and ]=*])
		local contentLine = trimmed:gsub("^%-%-%[=*%[%s*", ""):gsub("%s*]=*]$", "")
		if contentLine == "" then
			continue
		end
		trimmed = contentLine

		if trimmed:match("^@") then
			popStackTo(indentLen)
			local key, rest = trimmed:match("^@(%S+)%s*(.*)")
			local node = pushNode(key, indentLen)
			if rest and #rest > 0 then
				for arg in rest:gmatch("%S+") do
					table.insert(node.args, self:ParseValue(arg))
				end
			end
		elseif #stack > 0 and indentLen > stack[#stack].indent then
			local top = stack[#stack]
			top.current.textBuffer = top.current.textBuffer or {}
			table.insert(top.current.textBuffer, line)
		else
			popStackTo(0)
			if trimmed ~= "" then
				table.insert(docLines, trimmed)
			end
		end
	end

	popStackTo(0)
	return table.concat(docLines, "\n"), meta
end

function Parser:GetDocBeforeLine(lineIndex: number): (string, any)
	local j = lineIndex - 1

	while j >= 1 do
		local line = self.lines[j]
		local trimmed = line:match("^%s*(.*%S)") or ""

		-- Skip empty lines
		if trimmed == "" then
			j -= 1
			continue
		end

		-- Found the end of a block comment / docblock: ]=*]$
		local closeDelimiter = trimmed:match("%](=*)%]$")
		if closeDelimiter then
			local openPattern = "^%s*%-%-%[" .. closeDelimiter .. "%["
			local docLines = {}
			local k = j

			-- Search upwards for the matching start of the block
			while k >= 1 do
				table.insert(docLines, 1, self.lines[k])
				if self.lines[k]:match(openPattern) then
					return self:ExtractDocAndMeta(table.concat(docLines, "\n"))
				end
				k -= 1
			end

			break
		end

		-- Skip single-line comments (-- ...)
		if trimmed:match("^%-%-") then
			j -= 1
			continue
		end

		break
	end

	return "", {}
end

--// Analyzer //--
function Parser:Use(analyzerModule: ModuleScript)
	local analyzer = require(analyzerModule)
	table.insert(self.analyzers, analyzer)
	return self
end

function Parser:OnCall(signature: string, callback: (args: {any}, lineIndex: number) -> ())
	self.callHooks[signature] = callback
	return self
end

--// Argument Splitter //--
function Parser:SplitArguments(argStr: string): {any}
	local args = {}
	local depth = 0
	local inString = false
	local stringChar = nil

	local startIdx = 1

	for i = 1, #argStr do
		local c = argStr:sub(i, i)
		if not inString then
			if c == '"' or c == "'" or c == "`" then
				inString = true
				stringChar = c
			elseif c == "(" or c == "{" or c == "[" then
				depth += 1
			elseif c == ")" or c == "}" or c == "]" then
				depth -= 1
			elseif c == "," and depth == 0 then
				local argSeg = argStr:sub(startIdx, i - 1)
				table.insert(args, self:ParseValue(argSeg:match("^%s*(.-)%s*$")))
				startIdx = i + 1
			end
		else
			if c == stringChar and argStr:sub(i-1, i-1) ~= "\\" then
				inString = false
			end
		end
	end

	if startIdx <= #argStr then
		local argSeg = argStr:sub(startIdx)
		if #argSeg:match("^%s*(.-)%s*$") > 0 then
			table.insert(args, self:ParseValue(argSeg:match("^%s*(.-)%s*$")))
		end
	end

	return args
end

--// Parsing //--
function Parser:Run()
	-- Find returned table --
	local returnedName = self.source:match("return%s+__%(([%w_]+)%)") -- self.source:match("return%s+__%s*%(%s*(.-)%s*%)")
	local returnLine = nil
	for idx = #self.lines, 1, -1 do
		local line = self.lines[idx]
		if line:match("^%s*return%s+") then
			returnLine = line
			break
		end
	end

	if not returnedName and self.allowNonNodeal and returnLine then
		returnedName = returnLine:match("return%s+%(?%s*([%w_]+)%s*::")
		if not returnedName then
			returnedName = returnLine:match("return%s+%(?%s*([%w_]+)%s*%)?%s*::")
		end
		if not returnedName then
			returnedName = returnLine:match("return%s+([%w_]+)")
		end
	end

	if not returnedName then return nil end

	-- Initialize local tables --
	for kw, name in self.source:gmatch("([lc]%w+)%s+([%w_]+)%s*=%s*{}") do
		if kw == "local" or kw == "const" then
			self.tables[name] = self.tables[name] or {}
		end
	end

	-- Initialize local tables with contents --
	for kw, name, body in self.source:gmatch("([lc]%w+)%s+([%w_]+)%s*=%s*(%b{})") do
		if kw ~= "local" and kw ~= "const" then continue end
		self.tables[name] = self.tables[name] or {}

		-- Match dictionary keys: ["key"] = ...
		for k in body:gmatch("%[%s*[\"']([%w_]+)[\"']%s*%]%s*=") do
			self.tables[name][k] = self:CreateCompletionItem({
				name = k,
				type = "variable",
				kind = Enum.CompletionItemKind.Field,
				detail = "any"
			})
		end

		-- Match standard identifier keys: key = ...
		for k in body:gmatch("([%w_]+)%s*=") do
			if k ~= "local" and k ~= "const" and k ~= "function" and k ~= "then" and k ~= "else" and k ~= "elseif" and k ~= "end" then
				self.tables[name][k] = self.tables[name][k] or self:CreateCompletionItem({
					name = k,
					type = "variable",
					kind = Enum.CompletionItemKind.Field,
					detail = "any"
				})
			end
		end

		-- Match array string literals: "key"
		for k in body:gmatch("[\"']([%w_]+)[\"']") do
			self.tables[name][k] = self.tables[name][k] or self:CreateCompletionItem({
				name = k,
				type = "variable",
				kind = Enum.CompletionItemKind.Field,
				detail = "any"
			})
		end
	end

	-- Extract type declarations --
	self:ExtractTypeDeclarations()

	-- Parse require statements and track scope depth --
	local scopeDepth = 0
	for _, line in self.lines do
		local isStrict = (scopeDepth == 0)

		-- Un mot ne peut pas etre trouve par son motif s'il n'est pas dans la ligne : mesure sur
		-- 858 lignes, 3,85 ms -> 0,54 ms pour les six.
		for _, entry in ScopeWords do
			if string.find(line, entry.word, 1, true) then
				for _ in line:gmatch(entry.pattern) do scopeDepth += entry.step end
			end
		end

		if scopeDepth < 0 then scopeDepth = 0 end

		-- Le `.-` de ce motif rebroussait sur toute la ligne, pour chaque ligne : 1,45 -> 0,05 ms.
		local kw, varName

		if string.find(line, "require", 1, true) then
			kw, varName = line:match("([lc]%w+)%s+([%w_]+)%s*.-=%s*require")
		end

		if (kw == "local" or kw == "const") and varName then
			local reqStart = line:find("require%s*%(")
			if reqStart then
				local parenStart = line:find("%(", reqStart)
				if parenStart then
					local depth = 1
					local idx = parenStart + 1
					local len = #line
					local requirePath = nil
					while idx <= len do
						local c = line:sub(idx, idx)
						if c == "(" then
							depth += 1
						elseif c == ")" then
							depth -= 1
							if depth == 0 then
								requirePath = line:sub(parenStart + 1, idx - 1)
								break
							end
						end
						idx += 1
					end

					if requirePath then
						local resolvedInst = TypeResolver.ResolvePath(requirePath, self.module)

						if resolvedInst and resolvedInst:IsA("ModuleScript") then
							local returnedTable, _, exportedTypes = self:ResolveModule(resolvedInst, isStrict, "require")
							self.tables[varName] = returnedTable
							self.importedTypes[varName] = exportedTypes
						end
					end
				end
			end
		end

		-- Parse Extensible Dependencies
		for _, extractor in DependencyExtractors do
			if not string.find(line, extractor.plain, 1, true) then continue end

			for matchStr in string.gmatch(line, extractor.pattern) do
				local resolvedInst = extractor.resolve(self, matchStr)
				if resolvedInst and self.module then
					self:AddDependency(resolvedInst, isStrict, extractor.type)
				end
			end
		end

		for _, aliasExt in AliasExtractors do
			if string.find(line, aliasExt.plain, 1, true) then
				local varName, typeAnno, matchStr = string.match(line, aliasExt.pattern)
				if not matchStr then
					varName, matchStr = string.match(line, "([%w_]+)%s*=%s*" .. aliasExt.extractor.pattern)
				end
				if varName and matchStr then
					local resolvedInst = aliasExt.extractor.resolve(self, matchStr)
					if resolvedInst and resolvedInst:IsA("ModuleScript") then
						local returnedTable, _, exportedTypes = self:ResolveModule(resolvedInst, isStrict, aliasExt.extractor.type)
						self.tables[varName] = returnedTable
						self.importedTypes[varName] = exportedTypes
					end
				end
			end
		end
	end

	-- Parse typed local variables --
	for _, line in self.lines do
		local kw, varName, typeAndRest = line:match("^%s*([lc]%w+)%s+([%w_]+)%s*:%s*(.+)")
		if (kw == "local" or kw == "const") and varName and typeAndRest then
			local typeStr = typeAndRest
			local eqPos = typeAndRest:find("=")
			if eqPos then
				typeStr = typeAndRest:sub(1, eqPos - 1)
			end
			typeStr = typeStr:match("^%s*(.*%S)") or ""

			if varName ~= "function" and typeStr ~= "" then
				local parsed = TypeParser.Parse(typeStr)
				local resolvedFields = TypeResolver.Resolve(parsed, self)
				self.tables[varName] = resolvedFields
			end
		end
	end

	local i = 1
	while i <= #self.lines do
		local line = self.lines[i]
		local trimmed = line:match("^%s*(.*%S)") or ""

		-- Skip empty lines or standard comments
		if trimmed == "" or (trimmed:sub(1, 2) == "--" and not trimmed:match("^%-%-%[=%[")) then
			i += 1
			continue
		end

		local matchFound = false

		-- 1. Call Hook Detection --
		for sig, callback in self.callHooks do
			local s, e = line:find(sig, 1, true)
			if s then
				local parenPos = line:find("%(", e + 1)
				if parenPos then
					local parts = { line }
					local k = i + 1
					local depth = parenDepth(string.sub(line, parenPos), 0)

					while k <= #self.lines and depth > 0 do
						parts[#parts + 1] = self.lines[k]
						depth = parenDepth(self.lines[k], depth)
						k += 1
					end
					local argStr = depth == 0 and table.concat(parts, "\n"):sub(parenPos):match("^%b()") or nil
					if argStr then
						callback(self:SplitArguments(argStr:sub(2, -2)), i)
						matchFound = true
						break
					end
				end
			end
		end

		if matchFound then
			i += 1
			continue
		end

		-- 2. Function detection (hasSignature) --
		-- Le `gsub` etait rejoue trois fois par ligne : sans `<` il ne change rien, et sans le mot
		-- `function` aucun des deux motifs ne peut mordre.
		local stripped = string.find(line, "<", 1, true) and line:gsub("%b<>", "") or line
		local tName, sep, fName, fArgs

		if string.find(stripped, "function", 1, true) then
			tName, sep, fName, fArgs = stripped:match("function%s+([%w_]+)([:%.])([%w_]+)%s*(%b())")

			if not tName then
				tName, sep, fName = stripped:match("function%s+([%w_]+)([:%.])([%w_]+)%s*%(")
				if tName then
					local parts = { line }
					local k = i + 1
					local startPos = stripped:find("%(")
					local depth = parenDepth(string.sub(line, startPos), 0)

					while k <= #self.lines and depth > 0 do
						parts[#parts + 1] = self.lines[k]
						depth = parenDepth(self.lines[k], depth)
						k += 1
					end

					if depth == 0 then
						fArgs = table.concat(parts, "\n"):sub(startPos):match("^%b()")
					end
				end
			end
		end

		if tName and fName and fArgs then
			local args = fArgs:sub(2, -2)

			-- Return type detection (might span lines or be on the same line)
			local retType = nil
			local signatureEndK = i
			local sigDepth = nil

			while signatureEndK <= #self.lines do
				for c in string.gmatch(self.lines[signatureEndK], "[%(%)]") do
					if c == "(" then
						sigDepth = (sigDepth or 0) + 1
					elseif sigDepth then
						sigDepth -= 1
					end

					if sigDepth == 0 then break end
				end

				if sigDepth == 0 then
					retType = self.lines[signatureEndK]:match("%)%s*:%s*(.+)")
					break
				end

				signatureEndK += 1
			end

			local docText, meta = self:GetDocBeforeLine(i)
			self.tables[tName] = self.tables[tName] or {}

			local detail = fName .. "(" .. args .. ")"
			if retType and retType ~= "" then detail ..= ": " .. retType end

			local parsedSig = nil
			if args and args ~= "" then
				parsedSig = TypeParser.ParseSignature(`function {fName}({args})`)
			end

			local item = self:CreateCompletionItem({
				name = fName,
				table = tName,
				type = "function",
				kind = Enum.CompletionItemKind.Function,
				detail = detail,
				prototype = detail,
				methodes = { sep },
				documentation = docText,
				decorators = meta,
				arguments = parsedSig and parsedSig.arguments or nil,
			})

			-- Link return table if applicable
			if retType and retType ~= "" then
				local parsed = TypeParser.Parse(retType)
				local resolvedFields = TypeResolver.Resolve(parsed, self)
				item.next = resolvedFields
			end

			self.tables[tName][fName] = item
		else
			-- 2. Variable detection --
			local varPath, vName, value = line:match("^%s*([%w_%.]+)%.([%w_]+)%s*=%s*(.*)")

			if varPath and vName then
				-- Multi-line assignment
				if value:match("^%s*$") then
					local k = i + 1
					while k <= #self.lines do
						local nextLine = self.lines[k]:match("^%s*(.*%S)") or ""
						if nextLine ~= "" and nextLine:sub(1, 2) ~= "--" then
							value = nextLine
							break
						end
						k += 1
					end
				end

				-- Check that it's not a comparison by verifying no '==' following it
				if value and not value:match("^=") then
					self.tables[varPath] = self.tables[varPath] or {}

					if value:match("^function%s*%(") then
						local fArgs = value:match("function%s*(%b())")
						local retType = value:match("%)%s*:%s*(.+)")

						if not fArgs then
							local startPos = value:find("%(")
							if startPos then
								local parts = { value }
								local k = i + 1
								local depth = parenDepth(string.sub(value, startPos), 0)

								while k <= #self.lines and depth > 0 do
									local nextLine = self.lines[k]
									parts[#parts + 1] = nextLine
									depth = parenDepth(nextLine, depth)
									if depth == 0 then
										retType = nextLine:match("%)%s*:%s*(.+)")
									end
									k += 1
								end

								if depth == 0 then
									fArgs = table.concat(parts, " "):match("function%s*(%b())")
								end
							end
						end

						local args = fArgs and fArgs:sub(2, -2) or ""
						local detail = vName .. "(" .. args .. ")"
						if retType and retType ~= "" then detail ..= ": " .. retType end

						local docText, meta = self:GetDocBeforeLine(i)
						local item = self:CreateCompletionItem({
							name = vName,
							table = varPath,
							type = "function",
							kind = Enum.CompletionItemKind.Function,
							detail = detail,
							prototype = detail,
							methodes = { "." },
							documentation = docText,
							decorators = meta
						})

						if retType and retType ~= "" then
							local parsed = TypeParser.Parse(retType)
							local resolvedFields = TypeResolver.Resolve(parsed, self)
							item.next = resolvedFields
						end

						self.tables[varPath][vName] = item
					else
						local assertion = value:match("::%s*(.+)")
						local resolvedFields = {}
						local typeGuess = "unknown"
						if assertion then
							local parsed = TypeParser.Parse(assertion)
							resolvedFields, typeGuess = TypeResolver.Resolve(parsed, self)
						else
							if value:match("^%d") then typeGuess = "number"
							elseif value:match('^["\'`]') then typeGuess = "string"
							elseif value:match("true") or value:match("false") then typeGuess = "boolean"
							end
						end

						self.tables[varPath][vName] = self:CreateCompletionItem({
							name = vName,
							type = "variable",
							kind = Enum.CompletionItemKind.Variable,
							detail = typeGuess,
							methodes = { "." },
							next = next(resolvedFields) and resolvedFields or nil
						})
					end
				end
			end
		end
		i += 1
	end

	-- 3. External analyzers --
	self.tables[".calls"] = {}
	local tracked = TrackedUsages
	if next(tracked) then
		local sanitizedSource = self.source:gsub("%-%-%[(=*)%[(.-)%]%1%]", function(eq, content)
			local nl = ""
			for _ in string.gmatch(content, "\n") do nl ..= "\n" end
			return nl
		end)
		sanitizedSource = string.gsub(sanitizedSource, "%-%-[^\n]*", "")

		local cleanLines = string.split(sanitizedSource, "\n")

		self.moduleAliases = {}

		for lineIndex, line in cleanLines do
			for _, aliasExt in AliasExtractors do
				if string.find(line, aliasExt.plain, 1, true) then
					local v, m = line:match(aliasExt.pattern)
					if v and m then self.moduleAliases[v] = m end
				end
			end

			if not string.find(line, "(", 1, true) then
				continue
			end

			local init = 1
			while true do
				local s, e = string.find(line, "[%w_]+%s*%(", init)
				if not s then break end

				local matched = string.sub(line, s, e)
				local funcName = string.match(matched, "([%w_]+)")

				if funcName and tracked[funcName] then
					local before = string.sub(line, 1, s - 1)

					if string.match(before, "function%s*[%w_.:]*$") then
						init = e
						continue
					end

					local path = string.match(before, "([%w_.:]+)$") or ""
					local fullFuncName = path .. funcName

					local pathNamespace = string.match(path, "([%w_]+)[.:]$")

					if pathNamespace and self.moduleAliases[pathNamespace] then
						local resolvedNamespace = self.moduleAliases[pathNamespace]
						local sep = string.match(path, "([.:])$") or "."
						fullFuncName = resolvedNamespace .. sep .. funcName
					end

					if pathNamespace then
						local t = self.tables[pathNamespace]
						if t then
							if not (t[funcName] and type(t[funcName]) == "table" and t[funcName].isTrackedForUsages) then
								init = e
								continue
							end
						end
					end

					local cleanBefore = string.match(before, "(.-)[%w_%.:]*$") or ""
					cleanBefore = string.match(cleanBefore, "^(.-)%s*$") or ""

					local captured = true
					if cleanBefore == "" or cleanBefore == "then" or cleanBefore == "else" or cleanBefore == "do" or cleanBefore == "repeat" or string.match(cleanBefore, ";$") then
						captured = false
					end

					if captured then
						local strLine = tostring(lineIndex)
						self.tables[".calls"][strLine] = self.tables[".calls"][strLine] or {}
						self.tables[".calls"][strLine][fullFuncName] = {
							captured = true
						}
					end
				end

				init = e
			end
		end
	end

	for _, analyzer in self.analyzers do
		if type(analyzer) == "function" then
			analyzer(self)
		elseif type(analyzer) == "table" and analyzer.Run then
			analyzer:Run(self)
		end
	end

	local returnedTable = self.tables[returnedName]
	if not returnedTable then
		returnedTable = {}
		self.tables[returnedName] = returnedTable
	end

	if self.allowNonNodeal and returnLine then
		local lastDoubleColon = returnLine:match(".*::%s*(.+)$")
		if lastDoubleColon then
			local returnTypeStr = lastDoubleColon:match("^%s*(.*%S)") or ""
			if returnTypeStr and returnTypeStr ~= "" then
				local parsed = TypeParser.Parse(returnTypeStr)
				local resolvedFields = TypeResolver.Resolve(parsed, self)
				if resolvedFields and next(resolvedFields) ~= nil then
					returnedTable = resolvedFields
					self.tables[returnedName] = returnedTable
				end
			end
		end
	end

	return returnedTable, self.tables, self.exportedTypes
end

--// Public //--
ParsingHandler = setmetatable({
	MasterGraph = MasterGraph,
	RegisterDependencyExtractor = function(type: string, pattern: string, resolveFunc: (parser: any, match: string) -> ModuleScript?)
		-- Vide si le motif ne commence pas par du litteral : `find` le trouve partout, donc rien
		-- n'est saute et un extracteur venu de l'exterieur se comporte comme avant.
		table.insert(DependencyExtractors, {
			type = type,
			plain = string.match(pattern, "^([%w_:]+)") or "",
			pattern = pattern,
			resolve = resolveFunc
		})
	end,
	UpdateExecutionOrder = function(roots: {Instance}?)
		-- Sous pcall : une faute ici arrêtait toute l'indexation sans rien dire, et l'interface
		-- restait plantée sur le pourcentage atteint. Mieux vaut une passe ratée et un
		-- avertissement qu'un plugin qui ne rend plus la main.
		local ok, order = pcall(function()
			MasterGraph:FilterExcludedNodes(roots)

			local result, err = MasterGraph:ResolveExecutionOrder()

			if err then
				error(err, 0)
			end

			return result
		end)

		if not ok then
			warn("[Nodeal] ordre d'exécution non résolu : " .. tostring(order))
			return
		end

		-- Rendue à intervalle régulier. Poser l'attribut sur plusieurs centaines de modules dans
		-- une seule image gelait Studio le temps de la passe, ce qui se lit exactement comme un
		-- plugin bloqué.
		local lastYield = os.clock()

		for index, module in order do
			if module.Parent then
				module:SetAttribute("ResolvedPriority", index)
			end

			if os.clock() - lastYield > 0.005 then
				task.wait()
				lastYield = os.clock()
			end
		end
	end,
	GetDependents = function(moduleScript: ModuleScript): { ModuleScript }
		local dependents = {}
		local visited = {}
		local function visit(mod)
			if visited[mod] then return end
			visited[mod] = true
			local deps = Dependencies[mod]
			if deps then
				for dep in deps do
					-- Ajoute une seule fois. L'insertion se faisait avant le test de visite,
					-- donc un module atteint par plusieurs chemins revenait autant de fois qu'il
					-- y avait de chemins -- et chaque doublon coutait une reindexation complete.
					-- Mesure sur ce depot : RoundConstants rendait 53 entrees pour 22 modules.
					if not visited[dep] then
						table.insert(dependents, dep)
					end

					visit(dep)
				end
			end
		end
		visit(moduleScript)
		return dependents
	end,
	ClearModuleDecorators = ClearModuleDecorators,
	OnDecoratorsDiscovered = nil,
	DynamicDecorators = DynamicDecorators,
	DecoratorNameToProvider = DecoratorNameToProvider,
}, {
	__call = function(self, source: string, module: ModuleScript?, context: string?, allowNonNodeal: boolean?): (any, any, any)
		if context == "indexing" and module then
			RegisterDecorator.ClearTarget(module)
			ModuleCache[module] = nil
		end

		local parser = Parser.new(source, module, context, allowNonNodeal)

		for _, analyzer in Analyzers do
			if type(analyzer) == "function" then
				analyzer(parser)
				table.insert(parser.analyzers, analyzer)
			elseif type(analyzer) == "table" then
				if analyzer.Init then analyzer:Init(parser) end
				table.insert(parser.analyzers, analyzer)
			end
		end

		local ret, tables, types = parser:Run()
		if module and context == "indexing" then
			ModuleCache[module] = { ret, tables, types }
		end

		if tables and tables.__decorators and next(tables.__decorators) then
			if module then
				for decName in tables.__decorators do
					DecoratorNameToProvider[decName] = module
				end
			end
			if type(ParsingHandler.OnDecoratorsDiscovered) == "function" then
				ParsingHandler.OnDecoratorsDiscovered(module, tables.__decorators)
			end
		elseif module and DynamicDecorators[module] and not next(DynamicDecorators[module]) then
			DynamicDecorators[module] = nil
		end

		return ret, tables, types
	end
})

return ParsingHandler