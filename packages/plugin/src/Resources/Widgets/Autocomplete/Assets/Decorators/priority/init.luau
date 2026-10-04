local priority = {}

priority.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <priority: number>`
}

function priority.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: number): ()
	if not tonumber(value) then return end

	table.insert(ancestor, {
		script.Name,
		{value}
	})
end

return priority