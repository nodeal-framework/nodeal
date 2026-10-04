--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Concat<A: string, B: string>",
	documentation = "Concatenates two string literal union types into a single string union type.",
	args = { "A", "B" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local prefixes = args[1] and TypeResolver.ResolveStringLiteralUnion(args[1], parser) or {}
	local suffixes = args[2] and TypeResolver.ResolveStringLiteralUnion(args[2], parser) or {}

	local unionList = {}
	for _, p in prefixes do
		for _, s in suffixes do
			table.insert(unionList, '"' .. p .. s .. '"')
		end
	end
	table.sort(unionList)
	local typeName = #unionList > 0 and table.concat(unionList, " | ") or "string"

	return {}, typeName
end

return Type