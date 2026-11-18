local DocFormatter = require(script.Parent.Parent.DocFormatter)

local param = {}

param.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <name: string> [description: string]`,
	documentation = "Documents a parameter of the function."
}

-- Rendering spec consumed by DocFormatter.
-- Glyph alternatives: "→", "›", "▷", "▶", "»".
local documentation = {
	order = 10,
	group = "signature",
	glyph = "→",
}

function documentation.identity(values: { any }): any
	return type(values[1]) == "string" and values[1] or nil
end

function documentation.render(values: { any }): string?
	local name = values[1]
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local description = DocFormatter.joinTokens(values, 2)
	local line = documentation.glyph .. " " .. DocFormatter.formatStrong(name)

	if description ~= "" then
		line ..= " " .. DocFormatter.formatInline(description, true)
	end

	return line
end

param.documentation = documentation

function param.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
	DocFormatter.add(item, param.documentation, ...)
end

return param
