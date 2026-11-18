local yieldDoc = {}

yieldDoc.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} [description: string]`,
	documentation = "Documents that the function yields."
}

function yieldDoc.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, ...): ()
end

return yieldDoc
