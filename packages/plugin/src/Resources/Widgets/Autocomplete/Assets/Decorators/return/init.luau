local DocFormatter = require(script.Parent.Parent.DocFormatter)

local returnDoc = {}

returnDoc.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} [description: string]`,
	documentation = "Documents the return value of the function."
}

-- Rendering spec consumed by DocFormatter.
local documentation = {
	order = 20,
	group = "signature",
	glyph = "↩",
}

function documentation.render(values: { any }): string?
	local description = DocFormatter.joinTokens(values)
	if description == "" then
		return nil
	end

	return documentation.glyph .. " " .. DocFormatter.formatInline(description)
end

returnDoc.documentation = documentation

function returnDoc.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
	DocFormatter.add(item, returnDoc.documentation, ...)
end

return returnDoc
