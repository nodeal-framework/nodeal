--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

-- Settings --
local spinInfo = TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)

-- Services --
local TweenService = game:GetService("TweenService")

-- Constants --
local pluginFolder = script.Parent.Parent

local pluginName = pluginFolder:GetAttribute("Name")

local resources = pluginFolder.Resources

local widgets = resources.Widgets
local loaderTemplate = resources.Loader

-- Variables --
local queue: { Folder } = {}
local mounting = false

-- Functions --

-- The window exists at once, under a loader; its content is mounted later.
local function newDock(self: any, widgetFolder: Folder)
	local attributes = widgetFolder:GetAttributes()

	local widget = {}
	widget.name = widgetFolder.Name

	self.widgets[widget.name] = widget

	if not widgetFolder.Assets:FindFirstChild("Ui") then
		return
	end

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
	widget.dock.Enabled = attributes.InitialEnabled

	widget.loader = loaderTemplate:Clone()
	widget.loader.Label.Text = `Loading {widget.name}…`
	widget.loader.Parent = widget.dock

	TweenService:Create(widget.loader.Spinner.UIStroke.UIGradient, spinInfo, { Rotation = 360 }):Play()
end

local function newButton(self: any, widgetFolder: Folder)
	local widget = self.widgets[widgetFolder.Name]
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

local function mountWidget(self: any, widgetFolder: Folder)
	local widget = self.widgets[widgetFolder.Name]

	if widget.dock then
		for _, child in widgetFolder.Assets.Ui:GetChildren() do
			child.Parent = widget.dock
		end
	end

	widget.callback = require(widgetFolder[widgetFolder:GetAttribute("Loader")])

	if widget.callback.Init then
		widget.callback.Init(self, widget.name)
	end

	newButton(self, widgetFolder)
end

-- One widget per frame, in order: Studio stays responsive and the loaders keep turning.
local function runQueue(self: any)
	mounting = true

	while #queue > 0 do
		local widgetFolder = table.remove(queue, 1)
		local widget = self.widgets[widgetFolder.Name]

		local success, message = xpcall(mountWidget, debug.traceback, self, widgetFolder)
		if not success then
			warn(`[Nodeal] {widgetFolder.Name} failed to load:\n{message}`)
		end

		if widget.loader then
			widget.loader:Destroy()
			widget.loader = nil
		end

		task.wait()
	end

	mounting = false
end

local function openWidget(self: any, widgetFolder: Folder)
	if self.widgets[widgetFolder.Name] then return end

	newDock(self, widgetFolder)
	table.insert(queue, widgetFolder)

	if not mounting then
		task.spawn(runQueue, self)
	end
end

local function loadWidgets(self: any)
	_G.CanNodealLoop = true

	local orderedWidgets = widgets:GetChildren()

	table.sort(orderedWidgets, function(a: Folder, b: Folder)
		return (a:GetAttribute("Order") or math.huge) < (b:GetAttribute("Order") or math.huge)
	end)

	for _, widgetFolder: Folder in orderedWidgets do
		if widgetFolder:GetAttribute("Disabled") then
			-- Setup lifts this once it knows Nodeal is installed
			widgetFolder:GetAttributeChangedSignal("Disabled"):Once(function()
				openWidget(self, widgetFolder)
			end)

			continue
		end

		openWidget(self, widgetFolder)
	end
end

return loadWidgets
