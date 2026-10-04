local CompletionItem = {}

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,
	
	detail = "typeof(value: any): (string, boolean)",
	documentation = "Returns the type of a value, with support for custom metatable types. If the value has a `__type` field in its metatable, that type name is returned along with `true`. Otherwise, the normal type is returned with `false`.",

	overloads = 1
}

return CompletionItem
