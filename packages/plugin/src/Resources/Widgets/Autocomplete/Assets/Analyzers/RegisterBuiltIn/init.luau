return function(parser)
	parser:OnCall("game:RegisterBuiltIn", function(args, lineIndex)
		local builtInName, tableName = args[1], args[2]
		if not (builtInName and tableName) then return end

		local docText, meta = parser:GetDocBeforeLine(lineIndex)

		parser.tables[tableName] = parser.tables[tableName] or {}
		parser.tables[tableName].__builtin = parser:CreateCompletionItem({
			name = builtInName,
			label = builtInName,
			type = "builtin",
			kind = Enum.CompletionItemKind.Class,
			detail = builtInName,
			documentation = docText,
			decorators = meta
		})
	end)
end