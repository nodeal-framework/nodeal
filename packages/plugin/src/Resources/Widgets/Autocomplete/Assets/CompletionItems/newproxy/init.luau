local CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,
	
	detail = "newproxy(object: any, modifier: { [any]: any }?): Proxy",
	documentation = "Wraps an object in a proxy that supports property overrides and metamethods."
}

return CompletionItem
