local CompletionItem = {}

--// Completion //--
CompletionItem.methodes = { ":" }

CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Method,

	detail = "GetCalls(sourceOrModule: string?): { [any]: any }",
	documentation = "Returns the tracked function call-sites collected across the project, including line numbers and whether each call captured a return value.",
}

--// Args //--
CompletionItem.args = {
	function(calling: ModuleScript)
		local Assets = script.Parent.Parent.Parent.Parent
		local RegisterDecorator = require(Assets.Analyzers.RegisterDecorator)
		local aggregatedCalls = RegisterDecorator.GetAggregatedCalls and RegisterDecorator.GetAggregatedCalls(calling)

		local results = {}
		if aggregatedCalls then
			for modName, _ in aggregatedCalls do
				table.insert(results, {
					label = `"{modName}"`,
					kind = Enum.CompletionItemKind.Constant,
					detail = `Module: {modName}`,
				})
			end
		end

		return results
	end
}

return CompletionItem
