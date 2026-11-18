--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Types //--
export type DecoratorToken = {
	line: number,
	character: number,
	name: string,
}

export type ScanResult = {
	decorators: { DecoratorToken },
	code: { string },
	lines: { string },
}

--// Module //--
local Scanner = {}

-- Tous les motifs Luau du diagnostic vivent ici : les checks et l'orchestrateur ne font que
-- les consommer. Un seul endroit a corriger si la syntaxe Nodeal change.
Scanner.Patterns = {
	GetService = "(game%s*:%s*GetService%s*%(%s*[\"'])([^\"']+)",
	GetModule = "(game%s*:%s*GetModule%s*%(%s*[\"'])([^\"']+)",
	Require = "(require%s*%(%s*[\"'])([^\"']+)",

	RegisterService = "game%s*:%s*RegisterService%s*%(%s*[\"']([^\"']+)",
	RegisterModule = "game%s*:%s*RegisterModule%s*%(%s*[\"']([^\"']+)",
	RegisterBuiltIn = "game%s*:%s*RegisterBuiltIn%s*%(%s*[\"']([^\"']+)",

	Accessor = "local%s+([%w_]+)%s*=%s*_G%s*%(",
}

local RegistrationPatterns = {
	Scanner.Patterns.RegisterService,
	Scanner.Patterns.RegisterModule,
	Scanner.Patterns.RegisterBuiltIn,
}

function Scanner.splitLines(source: string): { string }
	local lines = {}
	local index = 1

	while true do
		local newlineStart = source:find("[\r\n]", index)

		if not newlineStart then
			table.insert(lines, source:sub(index))
			break
		end

		table.insert(lines, source:sub(index, newlineStart - 1))

		-- '\r\n' compte pour une seule ligne, '\r' et '\n' seuls aussi.
		if source:sub(newlineStart, newlineStart + 1) == "\r\n" then
			index = newlineStart + 2
		else
			index = newlineStart + 1
		end
	end

	return lines
end

-- Remplace le commentaire de ligne par des espaces pour garder les colonnes intactes. Les
-- chaines sont traversees, sinon un '--' dans un texte couperait la ligne en deux.
local function maskLineComment(text: string): string
	local quote: string? = nil
	local index = 1

	while index <= #text do
		local character = text:sub(index, index)

		if quote then
			if character == "\\" then
				index += 2
				continue
			end

			if character == quote then
				quote = nil
			end

			index += 1
			continue
		end

		if character == '"' or character == "'" then
			quote = character
			index += 1
			continue
		end

		if character == "-" and text:sub(index + 1, index + 1) == "-" then
			return text:sub(1, index - 1) .. string.rep(" ", #text - index + 1)
		end

		index += 1
	end

	return text
end

-- Un seul balayage : il rend les lignes de code (commentaires neutralises) et, tant qu'il y
-- est, la position des jetons '@decorateur'. L'analyse tourne a chaque edition, donc elle
-- reste lineaire et ne construit pas d'AST.
function Scanner.scan(source: string): ScanResult
	local lines = Scanner.splitLines(source)
	local code = {}
	local decorators = {}

	local level: string? = nil

	for index, text in ipairs(lines) do
		local pieces = {}
		local cursor = 1

		while cursor <= #text do
			if level then
				local closeStart, closeEnd = text:find("]" .. level .. "]", cursor)
				local stop = if closeStart then closeStart - 1 else #text

				local fragment = text:sub(cursor, stop)
				local indent = fragment:match("^%s*") or ""
				local name = fragment:match("^%s*@(%S+)")

				if name then
					name = name:gsub("[^%w_%-]+$", "")

					if name ~= "" then
						table.insert(decorators, {
							line = index,
							character = cursor + #indent,
							name = name,
						})
					end
				end

				table.insert(pieces, string.rep(" ", stop - cursor + 1))

				if not closeStart then
					cursor = #text + 1
					break
				end

				level = nil
				cursor = closeEnd + 1
			else
				local openStart, openEnd, equals = text:find("%-%-%[(=*)%[", cursor)

				if not openStart then
					table.insert(pieces, text:sub(cursor))
					break
				end

				table.insert(pieces, text:sub(cursor, openStart - 1))
				table.insert(pieces, string.rep(" ", openEnd - openStart + 1))

				level = equals or ""
				cursor = openEnd + 1
			end
		end

		code[index] = maskLineComment(table.concat(pieces))
	end

	return {
		decorators = decorators,
		code = code,
		lines = lines,
	}
end

function Scanner.forEachCall(line: string, pattern: string, callback: (character: number, name: string) -> ())
	local cursor = 1

	while true do
		local startIndex, endIndex, prefix, name = line:find(pattern, cursor)

		if not startIndex then
			break
		end

		callback(startIndex + #prefix, name)
		cursor = endIndex + 1
	end
end

-- Un nom possede par le fichier courant est valide avant meme que l'indexeur ne le voie.
function Scanner.collectDeclared(code: { string }): { [string]: boolean }
	local declared = {}

	for _, line in ipairs(code) do
		for _, pattern in RegistrationPatterns do
			local name = line:match(pattern)

			if name then
				declared[name] = true
			end
		end
	end

	return declared
end

-- Signature du handshake : `local __ = _G()` (ou n'importe quel nom d'accesseur).
function Scanner.findAccessor(code: { string }): string?
	for _, line in ipairs(code) do
		local accessor = line:match(Scanner.Patterns.Accessor)

		if accessor then
			return accessor
		end
	end

	return nil
end

return Scanner
