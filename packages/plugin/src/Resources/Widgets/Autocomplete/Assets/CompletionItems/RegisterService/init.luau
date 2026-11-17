local CompletionItem = {}

CompletionItem.type = "function"
CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "RegisterService(name: string, content: any?): ()",
	documentation = "Register a service in the nodeal environement."
}

return CompletionItem
