local CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "print(...: any): ()",
	documentation = "Prints all provided values to `Nodeal → Output`."
}

return CompletionItem
