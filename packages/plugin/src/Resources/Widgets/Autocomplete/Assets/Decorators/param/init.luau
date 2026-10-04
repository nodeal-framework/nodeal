local param = {}

param.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <name: string> [description: string]`,
	documentation = "Documents a parameter of the function."
}

function param.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
end

return param
