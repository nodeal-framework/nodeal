--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

-- Services --
local Studio = settings():GetService("Studio")

local CollectionService = game:GetService("CollectionService")
local PluginGuiService = game:GetService("PluginGuiService")

-- Constants --
local themeTag = "Nodeal:Theme"

-- Functions --
local function cleanSplit(str: string): { string }
	local parts = string.split(str, ",")

	for i, v in parts do
		parts[i] = string.match(v, "^%s*(.-)%s*$")
	end

	return parts
end

-- An attribute named _Property holds "StudioStyleGuideColor, Modifier".
local function applyTheme(instance: Instance)
	local theme = Studio.Theme

	for index: string, value: any in instance:GetAttributes() do
		if string.sub(index, 1, 1) ~= "_" or type(value) ~= "string" then continue end

		local parts = cleanSplit(value)
		local color = theme:GetColor(Enum.StudioStyleGuideColor[parts[1]], Enum.StudioStyleGuideModifier[parts[2] or "Default"])

		instance[string.sub(index, 2)] = color
	end
end

local function forceTheme()
	for _, instance in CollectionService:GetTagged(themeTag) do
		if instance:IsDescendantOf(PluginGuiService) then
			applyTheme(instance)
		end
	end
end

return function(_self: any)
	CollectionService:GetInstanceAddedSignal(themeTag):Connect(applyTheme)

	Studio.ThemeChanged:Connect(forceTheme)
	forceTheme()
end
