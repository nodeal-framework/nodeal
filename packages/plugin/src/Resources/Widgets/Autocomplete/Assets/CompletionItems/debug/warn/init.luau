local CompletionItem = {}

CompletionItem.methodes = { "." }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "warn(...: any): ()",
	documentation = "Prints all provided values to `Roblox → Output` with distinct yellow formatting.",

	learnMoreLink = "https://create.roblox.com/docs/reference/engine/globals/RobloxGlobals#warn"
}

return CompletionItem
