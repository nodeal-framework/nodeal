local alias = {}

alias.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <...name: string>`
}

function alias.apply(item: CompletionItem, ancestor: {[number]: {string | any}}, ...): ()
	local args = {...}
	if #args < 1 then return end

	for index: number, value: any in args do
		args[index] = tostring(value)
	end

	table.insert(ancestor, {
		script.Name,
		args
	})
end

return alias