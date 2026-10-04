--!native
--!optimize 2

local CollectionService = game:GetService("CollectionService")
local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Tagged<tag: string>",
	documentation = "Builds a union structural type for all instances currently bearing the specified CollectionService tag.",
	args = { "tag" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local tagName = args[1] and args[1].value
	if not tagName then return {}, "any" end

	local taggedInstances = {}
	pcall(function()
		taggedInstances = CollectionService:GetTagged(tagName)
	end)

	local fields = {}
	for _, instance in taggedInstances do
		local instanceFields = TypeResolver.BuildInstanceTreeFields(instance, parser)
		for k, v in instanceFields do
			fields[k] = v
		end
	end

	return fields, "union"
end

return Type