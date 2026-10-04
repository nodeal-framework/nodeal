--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Fields<K: string, V: any>",
	documentation = "Creates a table type with the given string literal keys mapping to the given value type.",
	args = { "K", "V" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local keysArg = args[1]
	local valueArg = args[2]
	if not keysArg then return {}, "table" end

	local stringLiterals = TypeResolver.ResolveStringLiteralUnion(keysArg, parser)
	local resolvedValueFields, valueTypeName = {}, "any"
	if valueArg then
		resolvedValueFields, valueTypeName = TypeResolver.Resolve(valueArg, parser)
	end

	local fields = {}
	for _, key in stringLiterals do
		fields[key] = parser:CreateCompletionItem({
			name = key,
			type = (valueArg and valueArg.type == "function") and "function" or "variable",
			kind = Enum.CompletionItemKind.Field,
			detail = valueTypeName,
			next = next(resolvedValueFields) and resolvedValueFields or nil
		})
	end
	return fields, "table"
end

return Type