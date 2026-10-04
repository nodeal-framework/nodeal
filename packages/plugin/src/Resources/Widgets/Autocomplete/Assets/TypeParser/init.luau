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

local TypeParser = {}

type Token = {
	type: string,
	value: any,
	pos: number
}

local function tokenize(str: string): { Token }
	local tokens = {}
	local i = 1
	local len = #str

	while i <= len do
		local char = str:sub(i, i)
		if char:match("%s") then
			i += 1
		elseif char == "-" and str:sub(i+1, i+1) == ">" then
			table.insert(tokens, { type = "->", value = "->", pos = i })
			i += 2
		elseif char:match("[%a_]") then
			local start = i
			while i <= len and str:sub(i, i):match("[%w_]") do
				i += 1
			end
			local val = str:sub(start, i - 1)
			table.insert(tokens, { type = "ID", value = val, pos = start })
		elseif char:match("%d") then
			local start = i
			while i <= len and str:sub(i, i):match("[%d%.]") do
				i += 1
			end
			local val = str:sub(start, i - 1)
			table.insert(tokens, { type = "NUMBER", value = tonumber(val) or val, pos = start })
		elseif char == '"' or char == "'" or char == "`" then
			local start = i
			local quote = char
			i += 1
			local escaped = false
			local val = ""
			while i <= len do
				local c = str:sub(i, i)
				if escaped then
					val ..= c
					escaped = false
				elseif c == "\\" then
					escaped = true
				elseif c == quote then
					i += 1
					break
				else
					val ..= c
				end
				i += 1
			end
			table.insert(tokens, { type = "STRING", value = val, pos = start })
		elseif char == "|" or char == "&" or char == "<" or char == ">" or char == "{" or char == "}" or char == "(" or char == ")" or char == "," or char == ":" or char == "." or char == "?" or char == ";" or char == "[" or char == "]" then
			table.insert(tokens, { type = char, value = char, pos = i })
			i += 1
		else
			table.insert(tokens, { type = "SYMBOL", value = char, pos = i })
			i += 1
		end
	end
	return tokens
end

local parseCache: { [string]: any } = {}
local parseCacheCount = 0

function TypeParser.ClearCache()
	table.clear(parseCache)
	parseCacheCount = 0
end

function TypeParser.Parse(str: string, isSignature: boolean?): any
	if type(str) ~= "string" or str == "" then
		return { kind = "reference", name = "any", path = { "any" } }
	end

	local cacheKey = (isSignature and "1:" or "0:") .. str
	local cached = parseCache[cacheKey]
	if cached ~= nil then
		return cached
	end

	-- Strip comments first
	local cleanStr = str:gsub("%-%-%[=*%[.-]=*%]", ""):gsub("%-%-[^\n]*", "")
	local tokens = tokenize(cleanStr)
	local index = 1

	local function peek(): Token?
		return tokens[index]
	end

	local function consume(expectedType: string?): Token
		local tok = tokens[index]
		if not tok then
			error("Unexpected end of input")
		end
		if expectedType and tok.type ~= expectedType then
			error("Expected " .. expectedType .. " but got " .. tostring(tok.type) .. " at pos " .. tostring(tok.pos))
		end
		index += 1
		return tok
	end

	local function match(expectedType: string): Token?
		local tok = tokens[index]
		if tok and tok.type == expectedType then
			index += 1
			return tok
		end
		return nil
	end

	local parseType -- forward declaration

	local function parseFunction(): any
		local generics = {}
		if match("<") then
			while peek() and peek().type ~= ">" do
				if peek() and peek().type == "ID" then
					table.insert(generics, consume("ID").value)
				end
				match(",")
			end
			match(">")
		end

		consume("(")

		local arguments = {}
		if not peek() or peek().type ~= ")" then
			while true do
				if peek() and peek().type == ")" then break end

				local argName = nil
				local argType = nil
				local optional = false

				if peek() and peek().type == "ID" and tokens[index+1] and (tokens[index+1].type == ":" or tokens[index+1].type == "?") then
					local idTok = consume("ID")
					argName = idTok.value
					if match("?") then optional = true end
					consume(":")
					argType = parseType()
					if optional and argType.kind ~= "optional" then
						argType = { kind = "optional", inner = argType }
					end
				else
					local parsed = parseType()
					if parsed.kind == "variadic" then
						argName = "..."
						argType = parsed
					elseif parsed.kind == "optional" then
						argType = parsed
						optional = true
						local inner = parsed.inner
						if inner and (inner.kind == "reference" or inner.kind == "basic") and type(inner.name) == "string" then
							argName = inner.name:sub(1, 1):lower() .. inner.name:sub(2)
						else
							argName = "arg"
						end
					elseif (parsed.kind == "reference" or parsed.kind == "basic") and type(parsed.name) == "string" then
						argType = parsed
						argName = parsed.name:sub(1, 1):lower() .. parsed.name:sub(2)
					else
						argType = parsed
						argName = "arg"
					end
				end

				local isOpt = optional or (argType and argType.kind == "optional") or false
				local isVar = (argName == "..." or (argType and (argType.kind == "variadic" or (argType.inner and argType.inner.kind == "variadic")))) or false

				table.insert(arguments, {
					name = argName,
					type = argType,
					optional = isOpt,
					isVariadic = isVar,
				})

				if not match(",") then
					break
				end
			end
		end
		consume(")")

		local returnType = { kind = "reference", name = "void", path = {"void"} }
		if match("->") then
			returnType = parseType()
		end

		return {
			kind = "function",
			generics = generics,
			arguments = arguments,
			args = arguments,
			returns = returnType,
			returnType = returnType,
		}
	end

	local function parsePrimary(): any
		local tok = peek()
		if not tok then
			error("Unexpected end of input in parsePrimary")
		end

		local result = nil

		if tok.type == "<" then
			result = parseFunction()
		elseif tok.type == "(" then
			-- Check if it's a function type `(A, B) -> C`
			local parenDepth = 1
			local scanIdx = index + 1
			local hasArrow = false
			while scanIdx <= #tokens do
				local t = tokens[scanIdx]
				if t.type == "(" then
					parenDepth += 1
				elseif t.type == ")" then
					parenDepth -= 1
					if parenDepth == 0 then
						local nextT = tokens[scanIdx + 1]
						if nextT and (nextT.type == "->" or nextT.type == ":") then
							hasArrow = true
						end
						break
					end
				end
				scanIdx += 1
			end

			if hasArrow then
				result = parseFunction()
			else
				consume("(")
				local elements = {}
				if not peek() or peek().type ~= ")" then
					while true do
						if peek() and peek().type == ")" then break end
						table.insert(elements, parseType())
						if not match(",") then break end
					end
				end
				consume(")")

				if #elements == 1 then
					result = elements[1]
				else
					result = {
						kind = "tuple",
						elements = elements
					}
				end
			end
		elseif tok.type == "{" then
			consume("{")
			if peek() and peek().type == "}" then
				consume("}")
				result = { kind = "table", fields = {} }
			else
				-- Check if it's an array type `{ Type }` vs `{ name: Type }`
				local isArray = true
				local scanIdx = index
				local bracesDepth = 0
				local parenDepth = 0
				local bracketDepth = 0
				while scanIdx <= #tokens do
					local t = tokens[scanIdx]
					if t.type == "{" then
						bracesDepth += 1
					elseif t.type == "}" then
						if bracesDepth == 0 then break end
						bracesDepth -= 1
					elseif t.type == "(" then
						parenDepth += 1
					elseif t.type == ")" then
						if parenDepth > 0 then parenDepth -= 1 end
					elseif t.type == "[" then
						bracketDepth += 1
					elseif t.type == "]" then
						if bracketDepth > 0 then bracketDepth -= 1 end
					elseif t.type == ":" and bracesDepth == 0 and parenDepth == 0 and bracketDepth == 0 then
						isArray = false
						break
					end
					scanIdx += 1
				end

				if isArray then
					local elemType = parseType()
					match(",")
					match(";")
					consume("}")
					result = {
						kind = "array",
						element = elemType,
						elementType = elemType,
					}
				else
					local fields = {}
					local indexer = nil
					while true do
						if peek() and peek().type == "}" then
							break
						end

						if peek() and peek().type == "[" then
							consume("[")
							local keyType = parseType()
							consume("]")

							local optional = false
							if match("?") then optional = true end

							consume(":")
							local valType = parseType()

							if keyType.kind == "literal" and keyType.literalType == "string" then
								fields[keyType.value] = { type = valType, optional = optional }
							else
								indexer = { key = keyType, value = valType }
							end
						elseif peek() and (peek().type == "ID" or peek().type == "STRING") then
							local nameTok = consume()
							local propName = nameTok.value

							local optional = false
							if match("?") then optional = true end

							consume(":")
							local valType = parseType()
							fields[propName] = { type = valType, optional = optional }
						else
							error("Expected property name or indexer in table type")
						end

						if not match(",") and not match(";") then
							break
						end
					end
					consume("}")
					result = {
						kind = "table",
						fields = fields,
						indexer = indexer
					}
				end
			end
		elseif tok.type == "." and tokens[index+1] and tokens[index+1].type == "." and tokens[index+2] and tokens[index+2].type == "." then
			consume(".") consume(".") consume(".")
			match(":") -- Handle both `...` and `...: type`
			local varType = { kind = "reference", name = "any", path = {"any"} }
			if peek() and peek().type ~= "," and peek().type ~= ")" and peek().type ~= ">" then
				varType = parseType()
			end
			result = {
				kind = "variadic",
				type = varType
			}
		elseif tok.type == "STRING" then
			consume()
			result = { kind = "literal", literalType = "string", value = tok.value }
		elseif tok.type == "NUMBER" then
			consume()
			result = { kind = "literal", literalType = "number", value = tok.value }
		elseif tok.type == "ID" then
			local idTok = consume()
			local name = idTok.value
			local isBasic = (name == "any" or name == "unknown" or name == "never" or name == "boolean" or name == "number" or name == "string" or name == "thread" or name == "buffer")

			if name == "true" or name == "false" then
				result = { kind = "literal", literalType = "boolean", value = (name == "true") }
			elseif name == "nil" then
				result = { kind = "basic", name = "nil" }
			elseif isBasic and not (peek() and peek().type == "." and not (tokens[index+1] and tokens[index+1].type == ".")) then
				result = { kind = "basic", name = name }
			else
				local path = { name }
				while peek() and peek().type == "." and not (tokens[index+1] and tokens[index+1].type == ".") do
					consume(".")
					local subId = consume("ID")
					table.insert(path, subId.value)
				end
				local sub = if #path > 1 then path[#path] else nil

				if match("<") then
					local args = {}
					while peek() and peek().type ~= ">" do
						table.insert(args, parseType())

						if peek() and peek().type == "." and tokens[index+1] and tokens[index+1].type == "." and tokens[index+2] and tokens[index+2].type == "." then
							consume(".") consume(".") consume(".")
						end

						if not match(",") then break end
					end
					consume(">")
					result = {
						kind = "generic",
						name = name,
						sub = sub,
						path = path,
						args = args,
						arguments = args,
					}
				elseif name == "typeof" and match("(") then
					local innerTokens = {}
					local depth = 1
					while true do
						local t = consume()
						if t.type == "(" then depth += 1
						elseif t.type == ")" then
							depth -= 1
							if depth == 0 then break end
						end
						table.insert(innerTokens, t.value)
					end
					result = {
						kind = "typeof",
						value = table.concat(innerTokens, "")
					}
				else
					result = {
						kind = isBasic and "basic" or "reference",
						name = name,
						sub = sub,
						path = path
					}
				end
			end
		else
			error("Unexpected token type " .. tostring(tok.type) .. " in parsePrimary")
		end

		while match("?") do
			result = {
				kind = "optional",
				inner = result
			}
		end

		return result
	end

	local function parseIntersection(): any
		local left = parsePrimary()
		if peek() and peek().type == "&" then
			local types = { left }
			while match("&") do
				table.insert(types, parsePrimary())
			end
			return {
				kind = "intersection",
				types = types,
				elements = types,
			}
		end
		return left
	end

	function parseType(): any
		local left = parseIntersection()
		if peek() and peek().type == "|" then
			local types = { left }
			while match("|") do
				table.insert(types, parseIntersection())
			end
			left = {
				kind = "union",
				types = types,
				elements = types,
			}
		end

		return left
	end

	local success, result = pcall(function()
		if isSignature then
			if peek() and peek().type == "ID" and (peek().value == "local" or peek().value == "const") then consume("ID") end
			if peek() and peek().type == "ID" and peek().value == "function" then consume("ID") end

			local name = nil
			if peek() and peek().type == "ID" then
				name = consume("ID").value
				while peek() and (peek().type == "." or peek().type == ":") do
					local sepTok = consume()
					if peek() and peek().type == "ID" then
						name ..= sepTok.value .. consume("ID").value
					end
				end
			end

			local generics = {}
			if match("<") then
				while peek() and peek().type ~= ">" do
					if peek() and peek().type == "ID" then
						table.insert(generics, consume("ID").value)
					end
					match(",")
				end
				match(">")
			end

			consume("(")

			local arguments = {}
			if not peek() or peek().type ~= ")" then
				while true do
					if peek() and peek().type == ")" then break end

					local argName = nil
					local argType = nil
					local optional = false

					if peek() and peek().type == "ID" and tokens[index+1] and (tokens[index+1].type == ":" or tokens[index+1].type == "?") then
						local idTok = consume("ID")
						argName = idTok.value
						if match("?") then optional = true end
						consume(":")
						argType = parseType()
						if optional and argType.kind ~= "optional" then
							argType = { kind = "optional", inner = argType }
						end
					else
						-- Fallback: If it's just a name without type, or just a type
						local parsed = parseType()
						if parsed.kind == "variadic" then
							argName = "..."
							argType = parsed
						elseif parsed.kind == "optional" then
							argType = parsed
							optional = true
							local inner = parsed.inner
							if inner and (inner.kind == "reference" or inner.kind == "basic") and type(inner.name) == "string" then
								argName = inner.name:sub(1, 1):lower() .. inner.name:sub(2)
							else
								argName = "arg"
							end
						elseif (parsed.kind == "reference" or parsed.kind == "basic") and type(parsed.name) == "string" and not parsed.sub then
							local firstChar = parsed.name:sub(1, 1)
							if firstChar == firstChar:upper() and firstChar ~= firstChar:lower() then
								-- PascalCase -> it's a type!
								argName = firstChar:lower() .. parsed.name:sub(2)
								argType = parsed
							else
								-- lowercase -> untyped param name
								argName = parsed.name
								argType = { kind = "reference", name = "any", path = {"any"} }
							end
						else
							argType = parsed
							argName = "arg"
						end
					end

					if match("=") then
						while peek() and peek().type ~= "," and peek().type ~= ")" do
							index += 1
						end
					end

					local isOpt = optional or (argType and argType.kind == "optional") or false
					local isVar = (argName == "..." or (argType and (argType.kind == "variadic" or (argType.inner and argType.inner.kind == "variadic")))) or false

					table.insert(arguments, {
						name = argName,
						type = argType,
						optional = isOpt,
						isVariadic = isVar,
					})

					if not match(",") then break end
				end
			end
			consume(")")

			local returnType = nil
			if match(":") or match("->") then
				returnType = parseType()
			end

			return {
				kind = "function",
				name = name,
				generics = generics,
				arguments = arguments,
				args = arguments,
				returns = returnType,
				returnType = returnType,
			}
		else
			local parsed = parseType()
			return parsed
		end
	end)

	local finalAst = nil
	if success then
		finalAst = result
	else
		-- warn(`TypeParser Error while parsing: "{str}"\nDetails: {result}`)
		local cleaned = str:match("^%s*(.-)%s*$") or "any"
		finalAst = { kind = "reference", name = cleaned, path = { cleaned } }
	end

	if parseCacheCount > 2000 then
		table.clear(parseCache)
		parseCacheCount = 0
	end
	parseCache[cacheKey] = finalAst
	parseCacheCount += 1

	return finalAst
end

function TypeParser.ExtractPrototype(code: string): string
	local args_open = string.find(code, "%(")
	if not args_open then return code end

	local args_close = args_open
	local depth = 0
	for i = args_open, #code do
		local b = string.byte(code, i)
		if b == 40 then depth += 1 elseif b == 41 then depth -= 1 end
		if depth == 0 then args_close = i; break end
	end

	local signature = string.sub(code, 1, args_close)
	local after = string.sub(code, args_close + 1)

	local colon_idx = string.find(after, ":")
	if colon_idx then
		local before_colon = string.sub(after, 1, colon_idx - 1)
		if not string.find(before_colon, "%S") then
			local i = colon_idx + 1
			local len = #after
			local parenDepth = 0
			local braceDepth = 0
			local bracketDepth = 0
			local genericDepth = 0
			local end_pos = colon_idx
			local hasStartedType = false
			local lastSignificantChar = ":"

			while i <= len do
				if hasStartedType and parenDepth == 0 and braceDepth == 0 and bracketDepth == 0 and genericDepth == 0 then
					local rest = after:sub(i)
					if rest:match("^%s+do%s") or rest:match("^%s+return%s") or rest:match("^%s+local%s") or rest:match("^%s+end%s*") then
						end_pos = i - 1
						break
					end
				end

				local c = after:sub(i, i)
				if c == "(" then
					parenDepth += 1
					hasStartedType = true
					lastSignificantChar = "("
				elseif c == ")" then
					if parenDepth > 0 then parenDepth -= 1 end
					lastSignificantChar = ")"
				elseif c == "{" then
					braceDepth += 1
					hasStartedType = true
					lastSignificantChar = "{"
				elseif c == "}" then
					if braceDepth > 0 then braceDepth -= 1 end
					lastSignificantChar = "}"
				elseif c == "[" then
					bracketDepth += 1
					hasStartedType = true
					lastSignificantChar = "["
				elseif c == "]" then
					if bracketDepth > 0 then bracketDepth -= 1 end
					lastSignificantChar = "]"
				elseif c == "<" then
					genericDepth += 1
					hasStartedType = true
					lastSignificantChar = "<"
				elseif c == ">" then
					if genericDepth > 0 then genericDepth -= 1 end
					lastSignificantChar = ">"
				elseif c == "\n" or c == "\r" then
					if hasStartedType and parenDepth == 0 and braceDepth == 0 and bracketDepth == 0 and genericDepth == 0 then
						if lastSignificantChar ~= "|" and lastSignificantChar ~= "&" and lastSignificantChar ~= "," and lastSignificantChar ~= ":" then
							end_pos = i - 1
							break
						end
					end
				elseif not c:match("%s") then
					hasStartedType = true
					lastSignificantChar = c
				end

				end_pos = i
				i += 1
			end

			signature ..= " " .. string.sub(after, colon_idx, end_pos)
		end
	end

	signature = string.gsub(signature, "%s+", " ")
	return string.match(signature, "^%s*(.-)%s*$") or ""
end

function TypeParser.ParseSignature(input: any): any
	if type(input) == "table" then
		input.cache = input.cache or {}
		if input.cache.signature then
			return input.cache.signature
		end

		local ast = TypeParser.Parse(input.prototype, true)
		input.cache.signature = ast

		return ast
	elseif type(input) == "string" then
		return TypeParser.Parse(input, true)
	end

	return nil
end

return TypeParser
