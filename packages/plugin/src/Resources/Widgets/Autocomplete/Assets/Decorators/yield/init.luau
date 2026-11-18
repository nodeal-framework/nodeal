local DocFormatter = require(script.Parent.Parent.DocFormatter)

local yieldDoc = {}

yieldDoc.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} [description: string]`,
	documentation = "Documents that the function yields."
}

-- Rendering spec consumed by DocFormatter.
local documentation = {
	order = 30,
	group = "behavior",
	glyph = "⧗",
}

function documentation.render(values: { any }): string?
	local description = DocFormatter.joinTokens(values)
	if description == "" then
		return nil
	end

	return documentation.glyph .. " " .. DocFormatter.formatInline(description)
end

yieldDoc.documentation = documentation

function yieldDoc.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
	DocFormatter.add(item, yieldDoc.documentation, ...)
end

return yieldDoc
