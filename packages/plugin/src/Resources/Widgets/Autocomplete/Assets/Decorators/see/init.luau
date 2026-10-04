local see = {}

see.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <url: string>`
}

function see.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: string): ()
	if type(value) ~= "string" then return end

	ancestor.learnMoreLink = value
end

return see