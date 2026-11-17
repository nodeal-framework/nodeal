local CompletionItem = {}

CompletionItem.type = "function"
CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "RegisterModule(name: string, content: any?): ()",
	documentation = "Register a module in the nodeal environment."
}

return CompletionItem
