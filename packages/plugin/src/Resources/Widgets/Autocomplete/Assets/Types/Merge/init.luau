--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Merge<A: table, B: table>",
	documentation = "Merges the fields of two table types into one.",
	args = { "A", "B" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local a = args[1]
	local b = args[2]

	local fieldsA, nameA = {}, nil
	if a then
		fieldsA, nameA = TypeResolver.Resolve(a, parser)
	end

	local fieldsB, nameB = {}, nil
	if b then
		fieldsB, nameB = TypeResolver.Resolve(b, parser)
	end

	local result = {}
	for k, v in fieldsA do
		result[k] = v
	end
	for k, v in fieldsB do
		result[k] = v
	end

	return result, "Merge<" .. (nameA or "any") .. ", " .. (nameB or "any") .. ">"
end

return Type