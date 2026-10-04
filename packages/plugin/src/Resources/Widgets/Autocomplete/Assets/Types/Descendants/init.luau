--!native
--!optimize 2

local ApiDump = require(script.Parent.Parent.ApiDump)
local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Descendants<path: string, className: string?>",
	documentation = "Extracts the descendants of the given Instance path, optionally filtered by ClassName.",
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
	local descendants = {}
	pcall(function()
		descendants = rootInstance:GetDescendants()
	end)

	for _, descendant in descendants do
		if className and className ~= "" and className ~= "any" then
			if descendant.ClassName ~= className then
				continue
			end
		end

		if descendant:IsA("ModuleScript") then
			local returnedTable, allTables, exportedTypes = parser:ResolveModule(descendant)
			fields[descendant.Name] = parser:CreateCompletionItem({
				name = descendant.Name,
				type = "variable",
				kind = Enum.CompletionItemKind.Module,
				detail = "typeof(require(" .. descendant.Name .. "))",
				next = returnedTable
			})
		else
			local classCompletion = ApiDump:GetAutoCompletion(descendant.ClassName) or {}
			fields[descendant.Name] = parser:CreateCompletionItem({
				name = descendant.Name,
				type = "variable",
				kind = Enum.CompletionItemKind.Field,
				detail = descendant.ClassName,
				next = classCompletion
			})
		end
	end

	return fields, "table"
end

return Type