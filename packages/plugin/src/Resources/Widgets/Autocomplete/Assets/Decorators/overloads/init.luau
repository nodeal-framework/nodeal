local overloads = {}

overloads.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <overloads: number>`
}

function overloads.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: boolean | number): ()
	if not value then return end
	
	table.insert(ancestor, {
		script.Name,
		(value == true and 1) or (tonumber(value) and value) or 0
	})
end

return overloads