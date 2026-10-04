local CompletionItem: CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	label = "_G()",
	kind = Enum.CompletionItemKind.Event,
	
	detail = "_G()",
	documentation = "Hooks this module into Nodeal and inject the custom environment."
}

return CompletionItem