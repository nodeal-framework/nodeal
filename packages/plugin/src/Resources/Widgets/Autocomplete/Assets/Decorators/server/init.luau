-- Modules --
local server = {}

server.completion = {
	kind = Enum.CompletionItemKind.Method,
	detail = `@{script.Name} <active: boolean> | <...decorator: decorator>`,
	overloads = 1,
	args = {
		{ "true", "false" }
	}
}

function server.apply(item: any, ancestor: { [number]: {string | any} }, ...): ()
	local rawArgs = {...}
	local regularArgs = {}
	local nestedNodes = {}

	for _, arg in rawArgs do
		if type(arg) == "table" and type(arg.type) == "string" and arg.args ~= nil then
			table.insert(nestedNodes, arg)
		else
			table.insert(regularArgs, arg)
		end
	end

	if #regularArgs == 0 then
		table.insert(regularArgs, true)
	end

	local active = regularArgs[1]

	if active == false then
		table.insert(ancestor, {
			script.Name,
			{false}
		})
		return
	end

	if #nestedNodes > 0 then
		local nestedMetadata
		if item.parser and item.parser.ApplyNestedDecorators then
			nestedMetadata = item.parser:ApplyNestedDecorators(item, nestedNodes)
		else
			nestedMetadata = {}
			for _, node in nestedNodes do
				table.insert(nestedMetadata, { node.type, node.args or {} })
			end
		end

		table.insert(ancestor, {
			script.Name,
			{ active },
			nestedMetadata
		})
	else
		table.insert(ancestor, {
			script.Name,
			{ active }
		})
	end
end

return server