--!native
--!optimize 2

--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local TypeResolver

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Extend<BaseType, NewType> | Extend<T: table>",
	documentation = "Extends types with sub-types for qualification (e.g. number.u8, Color3.f32). When wrapping Descendants<...>, automatically registers each descendant module as an extended type with its members.",
	args = { "Target", "Extensions" }
}

local function registerFromTable(baseTypeName: string, members: { [string]: any }, originModule: ModuleScript?)
	if not baseTypeName or type(members) ~= "table" then return end

	for memberName, memberData in members do
		if type(memberName) ~= "string" then continue end
		if memberName:sub(1, 2) == "__" then continue end
		if memberName == "new" or memberName == "get_dynamic" or memberName == "is_controller" then continue end

		local detail = `type {baseTypeName}.{memberName}`
		local doc = nil
		if type(memberData) == "table" then
			if memberData.completion and memberData.completion.documentation then
				doc = memberData.completion.documentation
			elseif memberData.documentation then
				doc = memberData.documentation
			end
		end

		TypeResolver.RegisterExtension(baseTypeName, memberName, {
			detail = detail,
			documentation = doc,
		}, originModule)
	end
end

function Type.resolve(args, parser)
	TypeResolver = TypeResolver or require(script.Parent.Parent.TypeResolver)

	if not args or #args == 0 then
		return {}, "any"
	end

	-- Case 1: 1 argument: Extend<T> (e.g. Extend<Descendants<"script", "ModuleScript">>)
	if #args == 1 then
		local innerArg = args[1]
		local resolvedFields, innerName = TypeResolver.Resolve(innerArg, parser)

		local originModule = parser and parser.module or nil

		if type(resolvedFields) == "table" then
			for typeName, fieldItem in resolvedFields do
				if type(typeName) ~= "string" or typeName:sub(1, 2) == "__" then continue end

				local subMembers = (type(fieldItem) == "table" and type(fieldItem.next) == "table") and fieldItem.next or nil
				if subMembers then
					registerFromTable(typeName, subMembers, originModule)
				elseif type(fieldItem) == "table" then
					registerFromTable(typeName, fieldItem, originModule)
				end
			end
		end

		-- Return the exact resolvedFields and innerName to preserve 100% of inner type fidelity
		return resolvedFields, innerName or "Extend"
	end

	-- Case 2: 2 arguments: Extend<BaseType, NewType>
	local baseNode = args[1]
	local newTypeNode = args[2]

	local baseName = nil
	if baseNode.kind == "literal" and type(baseNode.value) == "string" then
		baseName = baseNode.value
	elseif baseNode.name then
		baseName = baseNode.name
	elseif baseNode.kind == "reference" and baseNode.path then
		baseName = table.concat(baseNode.path, ".")
	end

	local originModule = parser and parser.module or nil
	local resolvedNewTypes, newTypeName = TypeResolver.Resolve(newTypeNode, parser)

	if baseName and baseName ~= "" then
		if type(resolvedNewTypes) == "table" and next(resolvedNewTypes) then
			registerFromTable(baseName, resolvedNewTypes, originModule)
		else
			local literalVal = newTypeNode.kind == "literal" and tostring(newTypeNode.value) or nil
			if literalVal then
				TypeResolver.RegisterExtension(baseName, literalVal, {
					detail = `type {baseName}.{literalVal}`
				}, originModule)
			end
		end
	end

	return resolvedNewTypes, newTypeName or "Extend"
end

return Type
