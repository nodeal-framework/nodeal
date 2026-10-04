local CompletionItem = {}

CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "GetNative(name: string): any?",
	documentation = "Get a native from the roblox environment."
}

return CompletionItem
