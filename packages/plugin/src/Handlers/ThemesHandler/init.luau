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

-- Constants --
local plugin: plugin
local class

-- Modules --

-- Variables --
local currentTheme = Studio.Theme

-- Functions --
local function getTagged(tag: string): { Instance? }
	local instances = CollectionService:GetTagged(tag)

	for _, instance in instances do
		if instance:IsDescendantOf(game.PluginGuiService) then continue end

		local index = table.find(instances, instance)
		table.remove(instances, index)
	end

	return instances
end

local function cleanSplit(str: string): { string? }
	local parts = string.split(str, ",")
	
	for i, v in ipairs(parts) do
		parts[i] = string.gsub(v, "^%s*(.-)%s*$", "%1")
	end
	
	return parts
end

function applyTheme(instance: GuiObject)
	currentTheme = Studio.Theme

	local attributes = instance:GetAttributes()
	for index: string, value: string in attributes do
		if string.sub(index, 1, 1) ~= "_" then continue end

		local property = string.sub(index, 2)
		local value = cleanSplit(value)
		
		local color = currentTheme:GetColor(Enum.StudioStyleGuideColor[value[1]], Enum.StudioStyleGuideModifier[value[2] or "Default"])

		instance[property] = color
	end
end

function forceTheme()
	local themeInstances = getTagged("Nodeal:Theme")
	
	for _, instance: GuiObject in themeInstances do
		if not instance:IsA("GuiObject") then end
		if not instance:FindFirstAncestorOfClass("DockWidgetPluginGui") then return end
		
		applyTheme(instance)
	end
end

return function(self: any)
	class = self
	plugin = class.plugin
	
	CollectionService:GetInstanceAddedSignal("Nodeal:Theme"):Connect(applyTheme)
	
	Studio.ThemeChanged:Connect(forceTheme)
	forceTheme()
end
