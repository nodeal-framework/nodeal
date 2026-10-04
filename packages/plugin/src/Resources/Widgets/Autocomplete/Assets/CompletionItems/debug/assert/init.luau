local CompletionItem = {}

CompletionItem.methodes = { "." }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,
	
	detail = "assert(value: T, message: any): T",
	documentation = "Halts thread execution and throws a error to `Roblox → Output` if value is nil or false.",
	
	learnMoreLink = "https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#assert"
}

return CompletionItem