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

-- Constants --
local pluginFolder = script.Parent.Parent

local pluginName = pluginFolder:GetAttribute("Name")

local modules = pluginFolder.Handlers
local resources = pluginFolder.Resources

local widgets = resources.Widgets

-- Modules --

-- Variables --

-- Functions --
local function newWidget(self: any, widgetFolder: Folder)
	local attributes = widgetFolder:GetAttributes()
	
	local widget = {}
	widget.name = widgetFolder.Name
	
	if widgetFolder.Assets:FindFirstChild("Ui") then
		local widgetInfo = DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState[attributes.InitialDockState],
			attributes.InitialEnabled,
			attributes.InitialEnabledShouldOverrideRestore,
			attributes.FloatingXSize,
			attributes.FloatingYSize,
			attributes.MinXSize,
			attributes.MinYSize
		)
		
		local widgetId = `{pluginName}{widget.name}`
		widget.dock = self.plugin:CreateDockWidgetPluginGui(widgetId, widgetInfo)
		widget.dock.Title = `{pluginName} → {widget.name}`
		widget.dock.Name = widgetId
		
		widget.dock.ResetOnSpawn = false
		
		for _, child in widgetFolder.Assets.Ui:GetChildren() do
			child.Parent = widget.dock
		end
	end
	
	self.widgets[widget.name] = widget
	
	widget.callback = require(widgetFolder[attributes.Loader])
	
	if widget.callback.Init then
		widget.callback.Init(self, widget.name)
	end
	
	if widget.dock then
		widget.dock.Enabled = attributes.InitialEnabled
	end
end

local function newButton(self: any, widgetFolder: Folder)
	local widget = self.widgets[widgetFolder.name]
	if widget.noButton then return end

	widget.button = self.toolbar:CreateButton(widget.defaultName or widgetFolder.Name, "Click to toggle it", widgetFolder.Icon.Texture)
	
	if widget.disabledButton then
		widget.button.Enabled = false
	end
	
	if widget.defaultIcon then
		widget.button.Icon = widget.defaultIcon
	end
	
	widget.button.ClickableWhenViewportHidden = true
	
	widget.button.Click:Connect(function()
		if table.find(self.disabled, widget.name) then return end
		
		if widget.callback.Clicked then
			widget.callback.Clicked(self, widget.name)
		elseif widget.dock then
			widget.dock.Enabled = not widget.dock.Enabled
		end
	end)
end

function loadWidgets(self: any)
	_G.CanNodealLoop = true
	
	local orderedWidgets = {}

	for _, widgetFolder: Folder in widgets:GetChildren() do
		local order = widgetFolder:GetAttribute("Order")
		orderedWidgets[order] = widgetFolder
	end

	for _, widgetFolder: Folder in orderedWidgets do
		if self.widgets[widgetFolder.name] then continue end
		
		if widgetFolder:GetAttribute("Disabled") then
			widgetFolder:GetAttributeChangedSignal("Disabled"):Once(function()
				local widget = newWidget(self, widgetFolder)
				newButton(self, widgetFolder)
			end)
			
			continue
		end

		local widget = newWidget(self, widgetFolder)
		newButton(self, widgetFolder)
	end
end

return loadWidgets
