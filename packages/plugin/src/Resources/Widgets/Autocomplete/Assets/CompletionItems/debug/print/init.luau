local CompletionItem = {}

CompletionItem.methodes = { "." }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "print(...: any): ()",
	documentation = "Prints all provided values to `Roblox → Output`.",

	learnMoreLink = "https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#print"
}

return CompletionItem