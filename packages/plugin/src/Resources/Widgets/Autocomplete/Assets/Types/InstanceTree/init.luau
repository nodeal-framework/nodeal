--!native
--!optimize 2

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "InstanceTree<path: string>",
	documentation = "Recursively builds a structural type representing an instance and its descendants.",
	args = { "path" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local pathStr = args[1] and args[1].value
	if not pathStr then return {}, "any" end

	local rootInstance = TypeResolver.ResolvePath(pathStr, parser.module)
	if not rootInstance then return {}, "any" end

	local fields = TypeResolver.BuildInstanceTreeFields(rootInstance, parser)
	return fields, rootInstance.ClassName
end

return Type