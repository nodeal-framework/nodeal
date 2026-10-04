--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "ValuesOf<T: table>",
	documentation = "Extracts all values from a given table type and returns them as a union type.",
	args = { "T" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local t = args[1]
	if not t then return {}, "any" end

	local fields, _ = TypeResolver.Resolve(t, parser)
	local result = {}
	local typesList = {}
	for _, item in fields do
		if item.next then
			for k, v in item.next do
				result[k] = v
			end
		end
		table.insert(typesList, item.completion and item.completion.detail or "any")
	end
	table.sort(typesList)
	local typeName = #typesList > 0 and table.concat(typesList, " | ") or "any"

	return result, typeName
end

return Type