--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "KeysOf<T: table>",
	documentation = "Extracts all string keys from a given table type and returns them as a string union type.",
	args = { "T" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local t = args[1]
	if not t then return {}, "never" end

	local fields, _ = TypeResolver.Resolve(t, parser)
	local keysList = {}
	for k in fields do
		table.insert(keysList, '"' .. k .. '"')
	end
	table.sort(keysList)
	local typeName = #keysList > 0 and table.concat(keysList, " | ") or "never"

	return {}, typeName
end

return Type