local build = {}

build.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <active: boolean>`,
	args = {
		{ "true", "false" }
	}
}

function build.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: boolean): ()
	if type(value) ~= "boolean" then return end

	if item.discovery.type ~= "indexing" or item.type ~= "function" then return end
	if (item.name == "Build") == value then return end

	table.insert(ancestor, {
		script.Name,
		{value}
	})
end

return build