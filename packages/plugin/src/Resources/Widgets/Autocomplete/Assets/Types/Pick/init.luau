--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Pick<T: table, K: string>",
	documentation = "Constructs a type by picking the set of properties K from table T.",
	args = { "T", "K" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local t = args[1]
	local keysNode = args[2]
	if not t then return {}, "any" end

	local fields, name = TypeResolver.Resolve(t, parser)
	local pickKeys = {}
	local keys = TypeResolver.ResolveStringLiteralUnion(keysNode, parser)
	for _, k in keys do
		pickKeys[k] = true
	end

	local result = {}
	for k, v in fields do
		if pickKeys[k] then
			result[k] = v
		end
	end

	return result, name
end

return Type