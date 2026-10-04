--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Omit<T: table, K: string>",
	documentation = "Constructs a type by picking all properties from table T and then removing K.",
	args = { "T", "K" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local t = args[1]
	local keysNode = args[2]
	if not t then return {}, "any" end

	local fields, name = TypeResolver.Resolve(t, parser)
	local omitKeys = {}
	local keys = TypeResolver.ResolveStringLiteralUnion(keysNode, parser)
	for _, k in keys do
		omitKeys[k] = true
	end

	local result = {}
	for k, v in fields do
		if not omitKeys[k] then
			result[k] = v
		end
	end

	return result, name
end

return Type