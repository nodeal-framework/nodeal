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
local ApiDump = require(Assets.ApiDump)
local utils = require(Resources.Modules.Utils)

Snippet.prefix = ":"

function Snippet.provide(origin: ModuleScript?, Autocomplete: any?): { any }
	local items = {}
	local seen = {}

	local ac = Autocomplete or require(Assets.Parent.Autocomplete)

	-- 1. Custom Services
	local originContext = origin and utils.module.get_context(origin) or {}
	for serviceName: string, serviceData: { [string]: any } in ac.ServicesCompletions do
		if seen[serviceName] then continue end

		local target = serviceData.discovery and serviceData.discovery.module
		if target and origin and target == origin then continue end

		local targetContext = target and utils.module.get_context(target) or {}
		if not utils.module.is_module_accessible(originContext, targetContext, serviceData) then
			continue
		end

		seen[serviceName] = true
		local newText = "local " .. serviceName .. ' = game:GetService("' .. serviceName .. '")'
		local completion = serviceData.completion or {}
		local doc = (completion.documentation and completion.documentation ~= "" and completion.documentation)
			or ("Returns the " .. serviceName .. " service.")

		local tags = nil
		if completion.tags then
			tags = {}
			for tag: any, _ in completion.tags do
				table.insert(tags, tag)
			end
		end

		table.insert(items, {
			label = Snippet.prefix .. serviceName,
			kind = Enum.CompletionItemKind.Snippet,
			tags = tags,
			detail = newText,
			newText = newText,
			documentation = { value = doc },
			codeSample = completion.example or newText,
		})
	end

	-- 2. Engine Services
	for _, entry in ApiDump:GetTagged("Service") do
		local serviceName = entry.Name
		if not serviceName or seen[serviceName] then continue end

		seen[serviceName] = true
		local newText = "local " .. serviceName .. ' = game:GetService("' .. serviceName .. '")'
		local isDeprecated = entry.Tags and table.find(entry.Tags, "Deprecated") ~= nil
		local tags = nil
		if isDeprecated then
			tags = { Enum.CompletionItemTag.Deprecated }
		end

		table.insert(items, {
			label = Snippet.prefix .. serviceName,
			kind = Enum.CompletionItemKind.Snippet,
			tags = tags,
			detail = newText,
			newText = newText,
			documentation = { value = "Returns the " .. serviceName .. " service." },
			learnMoreLink = "https://create.roblox.com/docs/reference/engine/classes/" .. serviceName,
			codeSample = newText,
		})
	end

	return items
end

return Snippet
