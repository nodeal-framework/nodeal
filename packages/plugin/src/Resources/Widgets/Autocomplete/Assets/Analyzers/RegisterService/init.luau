local RegisterDecorator = require(script.Parent.RegisterDecorator)

return function(parser)
	parser:OnCall("game:RegisterService", function(args, lineIndex)
		local service_name, table_name = args[1], args[2]
		if not service_name then return end
		if not table_name and parser.module then
			table_name = parser.module.Name
		end
		if not table_name then return end

		local docText, meta = parser:GetDocBeforeLine(lineIndex)

		parser.tables[table_name] = parser.tables[table_name] or {}
		parser.tables[table_name].__services = parser.tables[table_name].__services or {}
		table.insert(parser.tables[table_name].__services, parser:CreateCompletionItem({
			name = service_name,
			label = service_name,
			type = "service",
			kind = Enum.CompletionItemKind.Class,
			detail = service_name,
			documentation = docText,
			decorators = meta
		}))

		if parser.module then
			RegisterDecorator.AddService(parser.module, service_name, table_name)
		end
	end)

	parser:OnCall("game:RegisterModule", function(args, lineIndex)
		local module_name, table_name = args[1], args[2]
		if not module_name then return end
		if not table_name and parser.module then
			table_name = parser.module.Name
		end
		if not table_name then return end

		local docText, meta = parser:GetDocBeforeLine(lineIndex)

		parser.tables[table_name] = parser.tables[table_name] or {}
		parser.tables[table_name].__modules = parser.tables[table_name].__modules or {}
		table.insert(parser.tables[table_name].__modules, parser:CreateCompletionItem({
			name = module_name,
			label = module_name,
			type = "module",
			kind = Enum.CompletionItemKind.Class,
			detail = module_name,
			documentation = docText,
			decorators = meta
		}))

		if parser.module then
			RegisterDecorator.AddModule(parser.module, module_name, table_name)
		end
	end)
end