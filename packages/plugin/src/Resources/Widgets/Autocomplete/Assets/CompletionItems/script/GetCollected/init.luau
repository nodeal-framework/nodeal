local CompletionItem = {}

--// Completion //--
CompletionItem.methodes = { ":" }

CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Method,

	detail = "GetCollected(decoratorName: string?): { [any]: any }",
	documentation = "Returns the collected decorators registered for this module via meta-decorators (e.g. @collect). If decoratorName is specified, returns only the items for that decorator.",
}

--// Args //--
CompletionItem.args = {
	function(calling: ModuleScript)
		local Assets = script.Parent.Parent.Parent.Parent
		local RegisterDecorator = require(Assets.Analyzers.RegisterDecorator)
		local collected = RegisterDecorator.GetCollected and RegisterDecorator.GetCollected(calling) or (RegisterDecorator.CollectedDecorators and RegisterDecorator.CollectedDecorators[calling])

		local results = {}
		if collected then
			for decName, _ in collected do
				table.insert(results, {
					label = `"{decName}"`,
					kind = Enum.CompletionItemKind.Constant,
					detail = `Collected decorator: @{decName}`,
				})
			end
		end

		return results
	end
}

return CompletionItem
