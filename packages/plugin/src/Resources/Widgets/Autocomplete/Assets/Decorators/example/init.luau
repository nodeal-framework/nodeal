local example = {}

example.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <example: string>`
}

function example.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: string): ()
	if type(value) ~= "string" then return end

	ancestor.example = value:gsub("\t", "  ").."\n"
end

return example