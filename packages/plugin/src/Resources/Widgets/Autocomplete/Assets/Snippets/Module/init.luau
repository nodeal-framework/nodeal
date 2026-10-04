--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Snippet = {}

-- Constants --
local Assets = script.Parent.Parent
local Resources = Assets.Parent.Parent.Parent

-- Modules --
local utils = require(Resources.Modules.Utils)

Snippet.prefix = "$"

function Snippet.provide(origin: ModuleScript?, Autocomplete: any?): { any }
	local items = {}
	local originContext = origin and utils.module.get_context(origin) or {}
	local ac = Autocomplete or require(Assets.Parent.Autocomplete)

	for moduleName: string, itemData: { [string]: any } in ac.ModulesCompletions do
		local target = itemData.discovery and itemData.discovery.module
		if target and origin and target == origin then continue end
		if target and not target.Parent then continue end

		local targetContext = target and utils.module.get_context(target) or {}
		if not utils.module.is_module_accessible(originContext, targetContext, itemData) then
			continue
		end

		local completion = itemData.completion or {}
		if completion.hidden then continue end

		local newText = "local " .. moduleName .. ' = game:GetModule("' .. moduleName .. '")'
		local doc = (completion.documentation and completion.documentation ~= "" and completion.documentation)
			or ("Return a pointer to the content of " .. moduleName .. " module.")

		local tags = nil
		if completion.tags then
			tags = {}
			for tag: any, _ in completion.tags do
				table.insert(tags, tag)
			end
		end

		table.insert(items, {
			label = Snippet.prefix .. moduleName,
			kind = Enum.CompletionItemKind.Snippet,
			tags = tags,
			detail = newText,
			newText = newText,
			documentation = { value = doc },
			codeSample = completion.example or newText,
		})
	end

	return items
end

return Snippet
