--!native
--!optimize 2

local ApiDump = require(script.Parent.Parent.ApiDump)
local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Children<path: string, className: string?>",
	documentation = "Extracts the children of the given Instance path, optionally filtered by ClassName.",
	args = { "path", "className" }
}

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)
	local pathStr = args[1] and args[1].value
	local className = args[2] and args[2].value
	if not pathStr then return {}, "any" end

	local rootInstance = TypeResolver.ResolvePath(pathStr, parser.module)
	if not rootInstance then return {}, "any" end

	local fields = {}
	local children = {}
	pcall(function()
		children = rootInstance:GetChildren()
	end)

	for _, child in children do
		if className and className ~= "" and className ~= "any" then
			if child.ClassName ~= className then
				continue
			end
		end

		if child:IsA("ModuleScript") then
			local returnedTable, allTables, exportedTypes = parser:ResolveModule(child)
			fields[child.Name] = parser:CreateCompletionItem({
				name = child.Name,
				type = "variable",
				kind = Enum.CompletionItemKind.Module,
				detail = "typeof(require(" .. child.Name .. "))",
				next = returnedTable
			})
		else
			local classCompletion = ApiDump:GetAutoCompletion(child.ClassName) or {}
			fields[child.Name] = parser:CreateCompletionItem({
				name = child.Name,
				type = "variable",
				kind = Enum.CompletionItemKind.Field,
				detail = child.ClassName,
				next = classCompletion
			})
		end
	end

	return fields, "table"
end

return Type