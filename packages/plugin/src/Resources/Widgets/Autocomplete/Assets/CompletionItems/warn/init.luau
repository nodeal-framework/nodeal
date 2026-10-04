local CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "warn(...: any): ()",
	documentation = "Prints all provided values to `Nodeal → Output` with distinct yellow formatting."
}

return CompletionItem
