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
local maxHistory = 5

-- Services --
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Constants --
local Nodeal = script.Parent.Parent
local Resources = Nodeal.Resources

local Modules = Resources.Modules

local plugin

-- Modules --
local Dropdown = require(Modules.Dropdown)

-- Functions --
local function reversedCopy(array)
	local result = {}
	
	for i = #array, 1, -1 do
		table.insert(result, array[i])
	end
	
	return result
end

function mergeInto(t1, t2)
	for index: any, value: any in t2 do
		t1[index] = value
	end
end

-- Constants --
local tagsFunctions: { [string]: tagFunction } = {
	["Button:Hover"] = function(instance: GuiButton)
		local attributes = instance:GetAttributes()
		
		instance.MouseEnter:Connect(function()
			instance.BackgroundTransparency = attributes.Focused
		end)

		instance.MouseLeave:Connect(function()
			instance.BackgroundTransparency = attributes.UnFocused
		end)
		
		instance.MouseButton1Down:Connect(function()
			instance.BackgroundTransparency = attributes.UnFocused
		end)
		
		instance.MouseButton1Up:Connect(function()
			instance.BackgroundTransparency = attributes.Focused
		end)
	end,
	["Input:SearchBox"] = function(instance: TextBox)
		local attributes = instance:GetAttributes()
		
		local hasHistory: ImageButton = instance.Parent:FindFirstChild("History")
		local history = (hasHistory and plugin:GetSetting(`Nodeal:History:{attributes.Id}`) or {}) or nil
		
		instance.Focused:Connect(function()
			instance.Parent.UIStroke.Enabled = true
		end)
		
		instance.FocusLost:Connect(function(enterPressed: boolean)
			instance.Parent.UIStroke.Enabled = false
			
			if hasHistory and enterPressed and instance.Text ~= "" then
				local index = table.find(history, instance.Text)
				
				if index then
					table.remove(history, index)
				end
				
				table.insert(history, instance.Text)
				
				if #history > maxHistory then
					for i = 1, #history - maxHistory do
						table.remove(history, 1)
					end
				end
				
				plugin:SetSetting(`Nodeal:History:{attributes.Id}`, history)
			end
		end)
		
		instance:GetPropertyChangedSignal("Text"):Connect(function()
			instance.Parent.Cancel.Visible = instance.Text ~= ""
		end)
		
		instance.Parent.Cancel.MouseButton1Click:Connect(function()
			instance.Text = ""
		end)
		
		if hasHistory then
			local historyTab = {}
			
			local behavior = require(instance.Behavior)
			
			instance:GetPropertyChangedSignal("Text"):Connect(function()
				if instance.Text == "" then return end
				if not historyTab.Instance then return end
				
				historyTab:Destroy()
			end)
			
			hasHistory.MouseButton1Click:Connect(function()
				if historyTab.Instance then
					historyTab:Destroy()
				else
					local content = {
						{
							Type = "Container",
							Label = "History",
							Childs = {}
						}
					}
					
					if #history > 0 then
						for _, str: string in reversedCopy(history) do
							table.insert(content[1].Childs, {
								Type = "Button",
								Label = str,
								Function = function()
									instance.Text = str
									instance:CaptureFocus()
								end,
								Cancel = function()
									local index = table.find(history, str)
									table.remove(history, index)
									
									plugin:SetSetting(`Nodeal:History:{attributes.Id}`, history)
								end
							})
						end
					else
						table.insert(content[1].Childs, {
							Type = "Button",
							Label = "Empty",
							Function = function()
								instance:CaptureFocus()
								historyTab:Destroy()
							end,
						})
					end
					
					instance:CaptureFocus()
					
					local Widget = instance:FindFirstAncestorOfClass("DockWidgetPluginGui")
					local Popup = Widget:FindFirstChild("Overlay") or Widget:FindFirstChild("Popup")

					historyTab = Dropdown.new(Popup, behavior.getProperties, content, instance)
				end
			end)
		end
	end,
	["Gradient:Loading"] = function(instance: UIGradient)
		local tweenInfo = TweenInfo.new(
			1.5,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.In,
			-1
		)

		local propertyTable = {
			Offset = Vector2.new(2, 0)
		}

		local tween = TweenService:Create(instance, tweenInfo, propertyTable)
		tween:Play()

		instance.Destroying:Once(function()
			tween:Cancel()
		end)
	end,
	["ScrollBar:Showup"] = function(instance: Frame)
		local scrollingFrame = instance.Parent:FindFirstChildOfClass("ScrollingFrame")
		
		scrollingFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
			instance.Visible = scrollingFrame.AbsoluteCanvasSize.X ~= scrollingFrame.AbsoluteWindowSize.X
		end)
	end,
}

-- Modules --

-- Variables --

-- Functions --
local function isDescendant(instance: GuiObject, widgets: {}): boolean
	if instance:IsDescendantOf(workspace) then return end
	if instance:IsDescendantOf(game.StarterGui) then return end
	
	for _, widget: {} in widgets do
		if not widget.dock then continue end
		
		if instance:IsDescendantOf(widget.dock) then
			return true
		end
	end
	
	return false
end

local function getTagged(tag: string, widgets: {}): { GuiObject? }
	local instances = CollectionService:GetTagged(tag)

	for _, instance in instances do
		if isDescendant(instance, widgets) then continue end

		local index = table.find(instances, instance)
		table.remove(instances, index)
	end

	return instances
end

return function(self: any)
	plugin = self.plugin
	
	for tag: string, func: () -> () in tagsFunctions do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: GuiObject)
			if not isDescendant(instance, self.widgets) then return end
			func(instance)
		end)
		
		local instances = getTagged(tag, self.widgets)
		
		for _, instance: GuiObject in instances do
			func(instance)
		end
	end
end
