local returnDoc = {}

returnDoc.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} [description: string]`,
	documentation = "Documents the return value of the function."
}

function returnDoc.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
end

return returnDoc
