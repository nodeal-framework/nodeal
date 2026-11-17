local CompletionItem = {}

CompletionItem.type = "function"
CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "RegisterBuiltIn(name: string | dict, value: any?): ()",
	documentation = "Register a new built-in value in the global environement.",

	overloads = 1
}

return CompletionItem
