local CompletionItem = {}

CompletionItem.methodes = { "." }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "loading(name: string, percent: number?): ()",
	documentation = "Display a loading bar to `Nodeal → Output`."
}

return CompletionItem