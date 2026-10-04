local init = {}

init.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <active: boolean>`,
	args = {
		{ "true", "false" }
	}
}

function init.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: boolean): ()
	if type(value) ~= "boolean" then return end

	if item.discovery.type ~= "indexing" or item.type ~= "function" then return end
	if (item.name == "Init") == value then return end

	table.insert(ancestor, {
		script.Name,
		{value}
	})
end

return init