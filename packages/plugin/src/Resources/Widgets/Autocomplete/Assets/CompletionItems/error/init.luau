local CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "error(...: any): ()",
	documentation = "Halts thread execution and throws a error to `Roblox → Output` and `Nodeal → Output`."
}

return CompletionItem
