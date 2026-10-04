local CompletionItem = {}

CompletionItem.methodes = { "." }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,
	
	detail = "error(message: any, level: number?)",
	documentation = "Halts thread execution and throws a error to `Roblox → Output`.",
	
	learnMoreLink = "https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#error"
}

return CompletionItem