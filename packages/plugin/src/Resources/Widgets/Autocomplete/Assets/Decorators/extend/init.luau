--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local extend = {}

extend.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <item?: number> <itemType?: string> <child?: number> <childType?: string>`,
	documentation = "Registers a function as a dynamic completion extender. Calls to this function dynamically add new members and typed children to the caller table in autocompletion."
}

--[=[
    Applies the @extend decorator metadata to the decorated function item.
    Supports smart argument inference:
    - @extend (0 args): itemArg defaults to 1, itemType inferred from return type.
    - @extend <childType> (1 arg): itemType inferred from return type, childType set explicitly.
    - @extend <itemType> <childType> (2 args): itemType and childType set explicitly.
    - @extend <itemArg> <itemType> <childArg?> <childType?>: Full explicit positions.

    @param item The completion item representing the decorated function.
    @param ancestor The metadata list of the completion item.
    @param ... Variable arguments passed to the decorator tag.
]=]
function extend.apply(item: any, ancestor: { [number]: { string | any } }, ...: any): ()
	local rawArgs = { ... }

	-- 1. Infer return type using TypeParser AST and LuauParser
	local inferredReturnType = nil
	local TypeParser = require(script.Parent.Parent.TypeParser)
	local ast = TypeParser.ParseSignature(item)
	local ret = ast and ast.returns
	if ret then
		if ret.kind == "reference" and ret.name then
			inferredReturnType = ret.name
		elseif ret.kind == "optional" and ret.type and ret.type.name then
			inferredReturnType = ret.type.name
		elseif ret.name then
			inferredReturnType = ret.name
		end
	end

	if not inferredReturnType and item.prototype then
		local resourcesModules = script.Parent.Parent.Parent.Parent:FindFirstChild("Modules")
		local luauParserScript = resourcesModules and resourcesModules:FindFirstChild("LuauParser")
		if luauParserScript then
			local isSuccess, luauParser = pcall(require, luauParserScript)
			if isSuccess and luauParser and luauParser.functions and luauParser.functions.extract_infos then
				local infos = luauParser.functions.extract_infos(item.prototype)
				if infos and infos.returns and #infos.returns > 0 and infos.returns[1] ~= "void" and infos.returns[1] ~= "nil" then
					inferredReturnType = infos.returns[1]
				end
			end
		end
	end

	-- 2. Smart argument resolution
	local itemArg = 1
	local itemType = inferredReturnType
	local childArg = nil
	local childType = nil

	if #rawArgs == 0 then
		-- Zero args: rely purely on inferred return type and default argument 1
	elseif #rawArgs == 1 then
		local num = tonumber(rawArgs[1])
		if num then
			itemArg = num
		else
			local str = tostring(rawArgs[1])
			if inferredReturnType and inferredReturnType ~= str then
				-- If return type is already known, single string represents childType
				childType = str
			else
				itemType = str
			end
		end
	elseif #rawArgs == 2 then
		local num1 = tonumber(rawArgs[1])
		local num2 = tonumber(rawArgs[2])

		if num1 and num2 then
			itemArg = num1
			childArg = num2
		elseif num1 and not num2 then
			itemArg = num1
			itemType = tostring(rawArgs[2])
		elseif not num1 and num2 then
			itemType = tostring(rawArgs[1])
			childArg = num2
		else
			-- Both are strings: @extend <itemType> <childType>
			itemType = tostring(rawArgs[1])
			childType = tostring(rawArgs[2])
		end
	elseif #rawArgs == 3 then
		local num1 = tonumber(rawArgs[1])
		local num2 = tonumber(rawArgs[2])
		local num3 = tonumber(rawArgs[3])

		if num1 then
			itemArg = num1
			if not num2 then
				itemType = tostring(rawArgs[2])
				if num3 then
					childArg = num3
				else
					childType = tostring(rawArgs[3])
				end
			end
		else
			itemType = tostring(rawArgs[1])
			if num2 then
				childArg = num2
				childType = tostring(rawArgs[3])
			end
		end
	elseif #rawArgs >= 4 then
		itemArg = tonumber(rawArgs[1]) or 1
		itemType = tostring(rawArgs[2])
		childArg = tonumber(rawArgs[3])
		childType = tostring(rawArgs[4])
	end

	item.extend = {
		itemArg = itemArg,
		itemType = itemType,
		childArg = childArg,
		childType = childType,
	}

	local Resources = script.Parent.Parent.Parent.Parent.Parent
	local MetadataUtils = require(Resources.Modules.MetadataUtils)

	MetadataUtils.set(ancestor, script.Name, itemArg, itemType, childArg, childType)
end

return extend
