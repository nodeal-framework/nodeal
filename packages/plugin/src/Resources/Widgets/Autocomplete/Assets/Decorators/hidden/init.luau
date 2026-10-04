local hidden = {}

hidden.completion = {
	kind = Enum.CompletionItemKind.Snippet,
	detail = `@{script.Name} <hidden: boolean>`,
	args = {
		{ "true", "false" }
	}
}

function hidden.apply(item: CompletionItem, ancestor: { [number]: {string | any} }, value: boolean): ()
	if type(value) ~= "boolean" then return end

	ancestor.hidden = value
end

return hidden