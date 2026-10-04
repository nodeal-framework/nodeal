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

--// Parser //--
local Parser = {}
Parser.__index = Parser

type varData = { val: string, depth: number }

-- Private Functions & Lookups --
local decoratorLookup = nil
local methodLookup = nil

--[=[
    Splits a comma-separated parameter string into individual parameter declarations,
    handling nested brackets, braces, and parentheses.

    @param paramStr The string containing parameters inside parentheses.
    @return An array of parameter declaration strings.
]=]
local function splitParameters(paramStr: string): { string }
	local result = {}
	local current = ""
	local depth = 0

	for i = 1, #paramStr do
		local char = paramStr:sub(i, i)
		if char == "(" or char == "{" or char == "[" then
			depth += 1
			current ..= char
		elseif char == ")" or char == "}" or char == "]" then
			depth = math.max(0, depth - 1)
			current ..= char
		elseif char == "<" then
			depth += 1
			current ..= char
		elseif char == ">" then
			if paramStr:sub(i - 1, i - 1) ~= "-" then
				depth = math.max(0, depth - 1)
			end
			current ..= char
		elseif char == "," and depth == 0 then
			local trimmed = current:match("^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				table.insert(result, trimmed)
			end
			current = ""
		else
			current ..= char
		end
	end

	local finalTrimmed = current:match("^%s*(.-)%s*$")
	if finalTrimmed and finalTrimmed ~= "" then
		table.insert(result, finalTrimmed)
	end

	return result
end

local function hasRealInjectedParams(injectedParams: { any }?): boolean
	if not injectedParams or #injectedParams == 0 then
		return false
	end
	for _, p in injectedParams do
		local isGen = (p.isVariadic or p.name == "..." or p.name == nil)
			and (p.type == "any" or p.type == "any?" or p.type == nil)
		if not isGen then
			return true
		end
	end
	return false
end

--[=[
    Matches user-written parameters against injected parameters defined by decorators
    or callback signatures according to positional and name-matched rules.

    @param injectedParams Array of injected parameter definitions.
    @param userParams Array of user parameter declarations.
    @return Dictionary of assigned types { [paramName] = typeName }.
]=]
local function matchParameters(injectedParams: { any }, userParams: { any }): ({ [string]: string }, { [string]: any })
	local assignments = {}
	local matchedParams = {}
	if not injectedParams or #injectedParams == 0 or not userParams or #userParams == 0 then
		return assignments, matchedParams
	end

	local nonVarCount = 0
	local optCount = 0
	local hasVariadic = false
	local firstMandatoryIdx = nil

	for i, p in injectedParams do
		if p.isVariadic or p.name == "..." then
			hasVariadic = true
		else
			nonVarCount += 1
			if p.optional then
				optCount += 1
			else
				if not firstMandatoryIdx then
					firstMandatoryIdx = i
				end
			end
		end
	end

	local isAllOptional = (nonVarCount > 0 and optCount == nonVarCount and not hasVariadic)
	local injectedIdx = 1

	for userIdx, userParam in userParams do
		local uName = userParam.name
		local uType = userParam.explicitType

		if uType and uType ~= "" then
			assignments[uName] = uType
			if injectedIdx <= #injectedParams then
				matchedParams[uName] = injectedParams[injectedIdx]
				injectedIdx += 1
			end
			continue
		end

		if injectedIdx > #injectedParams then
			break
		end

		local currentInjected = injectedParams[injectedIdx]

		if isAllOptional then
			if not currentInjected.isVariadic and currentInjected.name ~= "..." then
				local typeName = currentInjected.type
				if type(typeName) == "table" then
					typeName = (typeName.kind == "optional" and typeName.inner and (typeName.inner.name or typeName.inner.kind))
						or typeName.name or (typeName.path and table.concat(typeName.path, ".")) or "any"
				end
				assignments[uName] = typeName
				matchedParams[uName] = currentInjected
				injectedIdx += 1
			end
		else
			local isLeadingOptional = currentInjected.optional and (
				(firstMandatoryIdx and injectedIdx < firstMandatoryIdx) or
				hasVariadic
			)

			if isLeadingOptional then
				local injName = (currentInjected.name or ""):lower()
				local usrName = (uName or ""):lower()
				local isMatch = (usrName == injName)
					or (injName:find(usrName, 1, true) ~= nil and #usrName >= 3)
					or (usrName:find(injName, 1, true) ~= nil and #injName >= 3)

				if isMatch then
					local typeName = currentInjected.type
					if type(typeName) == "table" then
						typeName = (typeName.kind == "optional" and typeName.inner and (typeName.inner.name or typeName.inner.kind))
							or typeName.name or (typeName.path and table.concat(typeName.path, ".")) or "any"
					end
					assignments[uName] = typeName
					matchedParams[uName] = currentInjected
					injectedIdx += 1
				else
					injectedIdx += 1
					if injectedIdx <= #injectedParams then
						local nextInjected = injectedParams[injectedIdx]
						if not nextInjected.isVariadic and nextInjected.name ~= "..." then
							local typeName = nextInjected.type
							if type(typeName) == "table" then
								typeName = (typeName.kind == "optional" and typeName.inner and (typeName.inner.name or typeName.inner.kind))
									or typeName.name or (typeName.path and table.concat(typeName.path, ".")) or "any"
							end
							assignments[uName] = typeName
							matchedParams[uName] = nextInjected
							injectedIdx += 1
						end
					end
				end
			else
				if not currentInjected.isVariadic and currentInjected.name ~= "..." then
					local typeName = currentInjected.type
					if type(typeName) == "table" then
						typeName = (typeName.kind == "optional" and typeName.inner and (typeName.inner.name or typeName.inner.kind))
							or typeName.name or (typeName.path and table.concat(typeName.path, ".")) or "any"
					end
					assignments[uName] = typeName
					matchedParams[uName] = currentInjected
					injectedIdx += 1
				end
			end
		end
	end

	return assignments, matchedParams
end

function Parser.new(source: string, line: number, character: number, lines: { string }?)
	local self = setmetatable({}, Parser)

	self.source = source
	self.targetLine = line
	self.targetChar = character
	self.lines = lines or source:split("\n")

	-- Bound checking
	if self.targetLine > #self.lines then self.targetLine = #self.lines end
	if self.targetLine < 1 then self.targetLine = 1 end

	self.varMap = {} :: { [string]: varData }
	self.varsByDepth = {} :: { [number]: { string } }
	self.maxDepth = 0
	self.isCursorInComment = false
	self.cleanedLines = {} :: { [number]: string }
	self.multiLineAtTarget = nil :: string?

	return self
end

--// Utilities //--
function Parser:CleanLine(lineStr: string, multiLineEquals: string?): (string, string?)
	local cleaned = ""
	local scannerPos = 1
	local lineLimit = #lineStr

	while scannerPos <= lineLimit do
		if multiLineEquals then
			local closePat = "]" .. multiLineEquals .. "]"
			local s, e = lineStr:find(closePat, scannerPos, true)
			if s then
				scannerPos = e + 1
				multiLineEquals = nil
			else
				scannerPos = lineLimit + 1
			end
		else
			local s = lineStr:find("%-%-", scannerPos)
			if s then
				cleaned ..= lineStr:sub(scannerPos, s - 1)
				local check = lineStr:sub(s + 2)
				local ob, eq = check:match("^(%[)(=*)(%[)")
				if ob then
					multiLineEquals = eq
					scannerPos = s + 2 + #eq + 2
				else
					scannerPos = lineLimit + 1
				end
			else
				cleaned ..= lineStr:sub(scannerPos)
				scannerPos = lineLimit + 1
			end
		end
	end

	return cleaned, multiLineEquals
end

--// Logic //--
function Parser:Analyze()
	local multiLineEquals: string? = nil
	local currentDepth = 0

	local function setVar(name: string, data: varData)
		self.varMap[name] = data
		local d = data.depth or 0
		if d > 0 then
			local list = self.varsByDepth[d]
			if not list then
				list = {}
				self.varsByDepth[d] = list
			end
			table.insert(list, name)
			if d > self.maxDepth then
				self.maxDepth = d
			end
		end
	end

	for i = 1, self.targetLine do
		local rawLine = self.lines[i] or ""
		local cleaned = ""
		local scannerPos = 1
		local lineLimit = #rawLine
		local isTargetLine = (i == self.targetLine)

		if isTargetLine then self.multiLineAtTarget = multiLineEquals end

		-- Sans `--` et hors commentaire long, le scanner ne ferait que recopier la ligne.
		if not multiLineEquals and not rawLine:find("%-%-", 1) then
			cleaned = rawLine
			scannerPos = lineLimit + 1
		end

		while scannerPos <= lineLimit do
			if multiLineEquals then
				local closePat = "]" .. multiLineEquals .. "]"
				local s, e = rawLine:find(closePat, scannerPos, true)

				if s then
					-- If target is within this multi-line comment
					if isTargetLine and self.targetChar > scannerPos and self.targetChar <= e then
						self.isCursorInComment = true
					end
					scannerPos = e + 1
					multiLineEquals = nil
				else
					if isTargetLine and self.targetChar > scannerPos then
						self.isCursorInComment = true
					end
					scannerPos = lineLimit + 1
				end
			else
				local s = rawLine:find("%-%-", scannerPos)
				if s then
					cleaned ..= rawLine:sub(scannerPos, s - 1)
					local check = rawLine:sub(s + 2)
					local ob, eq = check:match("^(%[)(=*)(%[)")

					if ob then
						multiLineEquals = eq
						scannerPos = s + 2 + #eq + 2
					else
						-- Single line comment
						if isTargetLine and self.targetChar > s then
							self.isCursorInComment = true
						end
						scannerPos = lineLimit + 1
					end
				else
					cleaned ..= rawLine:sub(scannerPos)
					scannerPos = lineLimit + 1
				end
			end
		end

		self.cleanedLines[i] = cleaned

		if cleaned ~= "" then
			-- Chaque motif est precede du mot qu'il exige : un `find` litteral coute bien moins qu'un motif joue pour rien.
			local hasLocal = string.find(cleaned, "local", 1, true) or string.find(cleaned, "const", 1, true)

			if (string.find(cleaned, "end", 1, true) or string.find(cleaned, "until", 1, true))
				and (cleaned:match("^%s*(end%f[%W]|until%f[%W])") or cleaned:find("end%)") or cleaned:find("end%s*,") or cleaned:find("end%s*$")) then
				if currentDepth > 0 then
					currentDepth -= 1
					for d = currentDepth + 1, self.maxDepth do
						local list = self.varsByDepth[d]
						if list then
							for _, varName in list do
								local v = self.varMap[varName]
								if v and v.depth > currentDepth then
									self.varMap[varName] = nil
								end
							end
							self.varsByDepth[d] = nil
						end
					end
				end
			end

			-- Variable Detection
			local kw, firstLocalName, firstLocalVal

			if hasLocal then
				for localKw, localName in cleaned:gmatch("([lc]%w+)%s+([%w_]+)%s*=") do
					if localKw == "local" or localKw == "const" then
						setVar(localName, { val = "unknown", depth = currentDepth })
					end
				end

				kw, firstLocalName, firstLocalVal = cleaned:match("([lc]%w+)%s+([%w_]+)%s*=%s*(.+)")
			end

			if (kw == "local" or kw == "const") and firstLocalName then
				setVar(firstLocalName, { val = firstLocalVal, depth = currentDepth })
			elseif string.find(cleaned, "=", 1, true) then
				local globName, globVal = cleaned:match("^%s*([%w_%.]+)%s*=%s*(.+)")
				if globName and globVal then
					local prefixKw = cleaned:match("^%s*(%a+)%s")
					if prefixKw ~= "local" and prefixKw ~= "const" then
						setVar(globName, { val = globVal, depth = currentDepth })
					end
				end
			end

			-- Annotated locals: `local X: Foo.Bar = ...`, que le motif ci-dessus ne peut pas traverser.
			if hasLocal then
				local annKw, annName, annType = cleaned:match("([lc]%w+)%s+([%w_]+)%s*:%s*([%w_%.]+)")
				if (annKw == "local" or annKw == "const") and annName then
					local entry = self.varMap[annName] or { val = annType or "unknown", depth = currentDepth }
					entry.val = annType or entry.val
					entry.typeAnnotation = annType
					setVar(annName, entry)
				end
			end

			-- Function parameter annotations and injected parameters
			if string.find(cleaned, "function", 1, true) then
				local tName, sep, fName, fParams = cleaned:match("function%s+([%w_]+)([:%.])([%w_]+)%s*(%b())")
				local fNameOnly, fParamsOnly = nil, nil
				if not tName then
					fNameOnly, fParamsOnly = cleaned:match("function%s+([%w_]+)%s*(%b())")
				end
				local anonParams = nil
				if not tName and not fNameOnly then
					anonParams = cleaned:match("function%s*(%b())")
				end

				local rawParams = fParams or fParamsOnly or anonParams
				if rawParams then
					local rawParamList = splitParameters(rawParams:sub(2, -2))
					local userParams = {}

					for _, p in rawParamList do
						local pName, pType = p:match("^([%w_]+)%s*:%s*(.+)$")
						if not pName then
							pName = p:match("^([%w_]+)$")
						end
						if pName then
							table.insert(userParams, { name = pName, explicitType = pType })
						end
					end

					-- Dot and colon method self handling
					local userParamsToMatch = {}
					for pIndex, pData in userParams do
						if pIndex == 1 and sep == "." and pData.name == "self" then
							setVar("self", { val = tName or "unknown", depth = currentDepth + 1 })
						else
							table.insert(userParamsToMatch, pData)
						end
					end
					if sep == ":" and tName then
						setVar("self", { val = tName, depth = currentDepth + 1 })
					end

					-- Check for injected parameters
					local injectedParams = nil
					local enclosingMethodItem = nil
					local attachedDec = nil

					-- 1. Attached Decorators (above the function)
					local inMultiComment = nil
					for scanLine = i - 1, math.max(1, i - 25), -1 do
						local rawLine = self.lines[scanLine] or ""
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
								if decoratorLookup then
									local dec = decoratorLookup(decName)
									if dec and dec.injectedParameters and hasRealInjectedParams(dec.injectedParameters) then
										injectedParams = dec.injectedParameters
										attachedDec = dec
										break
									end
								end
							end
							if injectedParams then break end

							local openMatch = rawLine:match("%-%-%[(=*)%[")
							if openMatch and openMatch == inMultiComment then
								inMultiComment = nil
							end
						else
							if rawLine:match("^%s*%-%-") then
								for decName in rawLine:gmatch("@([%w_]+)") do
									if decoratorLookup then
										local dec = decoratorLookup(decName)
										if dec and dec.injectedParameters and hasRealInjectedParams(dec.injectedParameters) then
											injectedParams = dec.injectedParameters
											attachedDec = dec
											break
										end
									end
								end
								if injectedParams then break end
							else
								break
							end
						end
					end

					-- 2. Enclosing Call (Callback argument)
					if not injectedParams and anonParams then
						local callerExpr, callSep, callMethod = nil, nil, nil

						local sep, method = cleaned:match("([:%.])([%w_]+)%s*%([^%)]*function")
						if method and sep then
							callSep = sep
							callMethod = method
							local s = cleaned:find(sep .. method .. "%s*%([^%)]*function")
							if s then
								callerExpr = cleaned:sub(1, s - 1):match("([%w_%.:]+)%s*$") or cleaned:sub(1, s - 1):match("^%s*(.-)%s*$")
							end
						else
							local standalone = cleaned:match("([%w_]+)%s*%([^%)]*function")
							if standalone and standalone ~= "function" then
								callMethod = standalone
								callSep = ""
								callerExpr = ""
							end
						end

						if not callMethod then
							for scanLine = i - 1, math.max(1, i - 5), -1 do
								local pLine = self.cleanedLines[scanLine] or ""
								local pSep, pMethod = pLine:match("([:%.])([%w_]+)%s*%([^%)]*$")
								if pMethod and pSep then
									callSep = pSep
									callMethod = pMethod
									local s = pLine:find(pSep .. pMethod .. "%s*%([^%)]*$")
									if s then
										callerExpr = pLine:sub(1, s - 1):match("([%w_%.:]+)%s*$") or pLine:sub(1, s - 1):match("^%s*(.-)%s*$")
									end
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

						if callMethod and methodLookup then
							enclosingMethodItem = methodLookup(self, callerExpr or "", callMethod, callSep or "")
							if enclosingMethodItem and enclosingMethodItem.arguments then
								for _, arg in enclosingMethodItem.arguments do
									if arg.type and arg.type.kind == "function" and arg.type.arguments then
										injectedParams = arg.type.arguments
										break
									end
								end
							end
						end
					end

					-- Apply matching
					local assignments, matchedParams = matchParameters(injectedParams or {}, userParamsToMatch)

					for _, p in userParamsToMatch do
						local assignedType = assignments[p.name] or p.explicitType
						local matched = matchedParams and matchedParams[p.name]
						local members = (matched and (matched.members or matched.next))
							or (enclosingMethodItem and enclosingMethodItem.context)
							or (attachedDec and attachedDec.context)
						setVar(p.name, {
							val = assignedType or "unknown",
							depth = currentDepth + 1,
							typeAnnotation = assignedType,
							members = members,
						})
					end
				end
			end

			if string.find(cleaned, "type", 1, true) then
				local typeName, typeVal = cleaned:match("^%s*type%s+([%w_]+)%s*=%s*(.+)")
				if not typeName then typeName, typeVal = cleaned:match("^%s*export%s+type%s+([%w_]+)%s*=%s*(.+)") end
				if typeName then
					setVar(typeName, { val = typeVal, depth = currentDepth, isType = true })
				end
			end

			-- Scope Entry
			if cleaned:match("^%s*(function%f[%W]|if%f[%W]|do%f[%W]|for%f[%W]|while%f[%W]|repeat%f[%W])")
				or cleaned:find("function%s*[%w_%.:]*%s*%b()") then
				currentDepth += 1
			end
		end
	end

	if multiLineEquals then
		self.isCursorInComment = true
	end
end

function Parser:ExtractRawExpression(): string
	-- 1. Collect recent lines to handle multi-line expressions
	-- Analyze a deja nettoye ces lignes : seules les dix dernieres servent, inutile de rebalayer depuis la ligne 1.
	local prefix = ""

	for j = math.max(1, self.targetLine - 9), self.targetLine - 1 do
		local rawLine = self.lines[j] or ""
		prefix ..= (self.isCursorInComment and rawLine or (self.cleanedLines[j] or "")) .. "\n"
	end

	local rawTarget = (self.lines[self.targetLine] or ""):sub(1, self.targetChar - 1)
	prefix ..= self.isCursorInComment and rawTarget or (self:CleanLine(rawTarget, self.multiLineAtTarget))

	-- 2. Determine if the cursor is already inside a string
	local inStringAtCursor = nil
	for j = 1, #prefix do
		local char = prefix:sub(j, j)
		local prevChar = prefix:sub(j - 1, j - 1)
		if inStringAtCursor then
			if char == inStringAtCursor and prevChar ~= "\\" then
				inStringAtCursor = nil
			end
		else
			if char == '"' or char == "'" or char == "`" then
				inStringAtCursor = char
			end
		end
	end

	-- 3. Strip assignment if present (only if not inside a string)
	if not inStringAtCursor then
		local eqPos = prefix:match("^.*()=%s*")
		if eqPos then prefix = prefix:sub(eqPos + 1) end
	end

	-- 4. Intelligent backward scan to find expression start
	local i = #prefix
	local stack = {}
	local currentInString = inStringAtCursor

	while i > 0 do
		local char = prefix:sub(i, i)
		local prevChar = prefix:sub(i - 1, i - 1)

		if currentInString then
			if char == currentInString and prevChar ~= "\\" then
				currentInString = nil
			end
		else
			if char == '"' or char == "'" or char == "`" then
				currentInString = char
			elseif char == ")" or char == "]" or char == "}" or char == ">" then
				table.insert(stack, char)
			elseif char == "(" or char == "[" or char == "{" or char == "<" then
				if #stack > 0 then table.remove(stack) end
			elseif #stack == 0 then
				if char:match("[;=]") then break end

				-- Stop at comment start if we're scanning backward
				if char == "-" and prevChar == "-" then break end

				if char:match("%s") then
					local foundSep = false

					for k = i - 1, 1, -1 do
						local c = prefix:sub(k, k)
						if c:match("[%.:%[%(%,%{]") then foundSep = true; break
						elseif not c:match("%s") then break end
					end

					if not foundSep then
						for k = i + 1, #prefix do
							local c = prefix:sub(k, k)
							if c:match("[%.:%[%(%,%{]") then foundSep = true; break
							elseif not c:match("%s") then break end
						end
					end

					if not foundSep or self.isCursorInComment then break end
				end
			end
		end
		i -= 1
	end

	-- Safely reconstruct the expression
	local result = ""
	local inStr: string? = nil
	local multiLineLevel: string? = nil
	local k = i + 1

	while k <= #prefix do
		local char = prefix:sub(k, k)

		if inStr then
			result ..= char
			if char == inStr then
				local backslashes = 0
				local bIdx = k - 1
				while bIdx > 0 and prefix:sub(bIdx, bIdx) == "\\" do
					backslashes += 1
					bIdx -= 1
				end
				-- If number of backslashes is even, the quote is NOT escaped
				if backslashes % 2 == 0 then inStr = nil end
			end
			k += 1
		elseif multiLineLevel then
			result ..= char
			local closePat = "]" .. multiLineLevel .. "]"
			if result:sub(-#closePat) == closePat then
				multiLineLevel = nil
			end
			k += 1
		else
			if char == '"' or char == "'" or char == "`" then
				inStr = char
				result ..= char
				k += 1
			elseif char == "[" then
				-- Check for Luau long strings: [=[ ... ]=]
				local start, finish, equals = prefix:find("%[(=*)%[", k)
				if start == k and finish then
					multiLineLevel = equals
					if not self.isCursorInComment then
						result ..= prefix:sub(start, finish)
					end
					k = finish + 1
				else
					if not char:match("%s") then result ..= char end
					k += 1
				end
			elseif not char:match("%s") or self.isCursorInComment then
				result ..= char
				k += 1
			else
				-- Skip whitespace in code, but keep it in comments if needed
				k += 1
			end
		end
	end

	return result
end

function Parser:Resolve(expr: string, depth: number, visited: { [string]: boolean }): string
	if not expr or expr == "" then return "" end
	if depth > 10 then return expr end

	expr = expr:gsub(";%s*$", ""):match("^%s*(.-)%s*$") or ""

	-- 1. Exact match check in O(1)
	local exactData = self.varMap[expr]
	if exactData and not visited[expr] then
		visited[expr] = true
		if exactData.members or exactData.val == "any" or exactData.val == "unknown" then
			return expr
		end
		return self:Resolve(exactData.val, depth + 1, visited)
	end

	-- 2. Prefix check from longest prefix to shortest in O(1)
	local sepIndices = {}
	local len = #expr
	for i = 1, len do
		local b = string.byte(expr, i)
		if b == 46 or b == 58 then -- '.' or ':'
			table.insert(sepIndices, i)
		elseif b == 40 or b == 91 or b == 123 then -- '(', '[', '{'
			break
		end
	end

	for idx = #sepIndices, 1, -1 do
		local sepPos = sepIndices[idx]
		local prefix = expr:sub(1, sepPos - 1)
		local data = self.varMap[prefix]
		if data and not visited[prefix] then
			visited[prefix] = true
			if data.members or data.val == "any" or data.val == "unknown" then
				return expr
			end
			local resolved = self:Resolve(data.val, depth + 1, visited)
			return resolved .. expr:sub(sepPos)
		end
	end

	return expr
end

--// Parsing //--
function Parser:Run(): (string, boolean)
	self:Analyze()

	local rawExpr = self:ExtractRawExpression()

	if self.isCursorInComment then
		return rawExpr:match("^%s*(.-)%s*$") or "", true
	end

	if not rawExpr or rawExpr == "" then
		return "", false
	end

	return self:Resolve(rawExpr, 0, {}), false
end

--// Public //--
local export = setmetatable({
	SetLookups = function(decLookup, methLookup)
		decoratorLookup = decLookup
		methodLookup = methLookup
	end,
	Parser = Parser,
	splitParameters = splitParameters,
	matchParameters = matchParameters,
}, {
	__call = function(self, source: string, line: number, character: number, lines: { string }?)
		local parser = Parser.new(source, line, character, lines)
		local res1, res2 = parser:Run()
		return res1, res2, parser
	end,
})

return export