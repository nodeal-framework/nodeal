--!native
--!optimize 2

local ApiDump = require(script.Parent.Parent.ApiDump)
local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "AttributesOf<path: string>",
	documentation = "Extracts the attributes of the given Instance path and maps them to their respective types.",
	args = { "path" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local pathStr = args[1] and args[1].value
	if not pathStr then return {}, "any" end

	local instance = TypeResolver.ResolvePath(pathStr, parser.module)
	if not instance then return {}, "any" end

	local fields = {}
	local attributes = {}
	pcall(function()
		attributes = instance:GetAttributes()
	end)

	for name, value in attributes do
		local typeGuess = typeof(value)
		local classCompletion = {}
		if typeGuess ~= "string" and typeGuess ~= "number" and typeGuess ~= "boolean" then
			classCompletion = ApiDump:GetAutoCompletion(typeGuess) or {}
		end
		fields[name] = parser:CreateCompletionItem({
			name = name,
			type = "variable",
			kind = Enum.CompletionItemKind.Property,
			detail = typeGuess,
			next = classCompletion
		})
	end

	return fields, "table"
end

return Type