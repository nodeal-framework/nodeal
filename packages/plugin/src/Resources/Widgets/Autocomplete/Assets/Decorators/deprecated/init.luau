local deprecated = {}

deprecated.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <deprecated: boolean>`,
	args = {
		{ "true", "false" }
	}
}

function deprecated.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: boolean): ()
	if type(value) ~= "boolean" then return end

	ancestor.tags = ancestor.tags or {}
	ancestor.tags.Deprecated = value
end

return deprecated