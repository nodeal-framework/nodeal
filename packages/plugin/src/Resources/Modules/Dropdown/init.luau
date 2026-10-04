--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Dropdown = {}

-- Services --
local UserInputService = game:GetService("UserInputService")

-- Constants --
local Childrens = script.Childrens

-- Variables --
local Popup

-- Functions --
function mergeInto(t1, t2)
	for _, v in ipairs(t2) do
		table.insert(t1, v)
	end
end

local customInteractions
customInteractions = {
	["Container"] = {
		Display = function(instance: GuiObject, component: {})
			instance.Header.Label.Text = component.Label
		end
	},
	["Toggle"] = {
		Display = function(instance: GuiObject, component: {})
			instance.Label.Text = component.Label
			
			instance.Toggled:GetPropertyChangedSignal("Value"):Connect(function()
				customInteractions.Toggle.Update(instance, instance.Toggled.Value)
				
				if component.Function then
					local finished = component.Function(instance.Toggled.Value, instance)
					
					if finished then
						component.Finish()
					end
				end
			end)
			
			if component.Default then
				instance.Toggled.Value = true
			end
		end,
		Interact = function(instance: GuiObject, component: {})
			instance.Toggled.Value = not instance.Toggled.Value
		end,
		Update = function(instance: typeof(Childrens.Toggle), value: boolean)
			local box = instance.Container.Box
			
			if value then
				box.BackgroundTransparency = 0
				box.Icon.Visible = true
				box.UIStroke.Color = Color3.fromRGB(60, 100, 250)
			else
				box.BackgroundTransparency = 1
				box.Icon.Visible = false
				box.UIStroke.Color = Color3.fromRGB(229, 229, 229)
			end
		end
	},
	["Button"] = {
		Display = function(instance: GuiObject, component: {})
			instance.Label.Text = component.Label
		end,
		Interact = function(instance: GuiObject, component: {})
			if component.Function then
				local finished = component.Function(nil, instance)
				
				if finished then
					component.Finish()
				end
			end
		end,
	}
}

local methodes = {}
methodes.__index = methodes

function methodes:LoadComponent(parent: GuiObject, component: {})
	local functions = customInteractions[component.Type] or {}
	local connections = {}

	local instance = Childrens[component.Type]:Clone() :: ImageButton

	if functions.Display then
		functions.Display(instance, component)
	end

	component.Finish = function()
		self:Destroy()
	end

	if component.Function then
		table.insert(connections, instance.MouseButton1Click:Connect(function()
			local result = nil
			
			if functions.Interact then
				functions.Interact(instance, component)
			end
			
			if self.Update then
				task.delay(0.1, function()
					self.Update(result)
				end)
			end
		end))
	end

	if component.Cancel then
		table.insert(connections, instance.Cancel.MouseButton1Click:Once(function()
			component.Cancel()
			
			for _, connection: RBXScriptConnection in connections do
				connection:Disconnect()
			end
			instance:Destroy()
		end))
		instance.Cancel.Visible = true
	end

	if component.Type == "Container" then
		self:LoadFromArray(instance.Body, component.Childs)
	end

	mergeInto(self.Connections, connections)
	
	instance.Parent = parent
end

function methodes:LoadFromArray(parent: GuiObject, content: { [number]: {} })
	for _, component: {} in content do
		self:LoadComponent(parent, component)
	end
end

function methodes:Clear()
	for _, child: GuiObject? in self.Instance:GetChildren() do
		if not child:IsA("GuiObject") then continue end
		
		child:Destroy()
	end
end

function methodes:Destroy()
	if not self.Instance or not self.Instance.Parent then return end
	Popup = nil
	
	for _, connection: RBXScriptConnection in self.Connections do
		connection:Disconnect()
	end
	
	self.Instance:Destroy()
	self.Instance = nil
end

function Dropdown.new(parent: GuiObject, properties: () -> {}, content: {}?, _: TextBox, update: () -> ())
	local self = setmetatable({}, methodes)
	
	if Popup then
		Popup:Destroy()
	end
	Popup = self
	
	self.Connections = {}
	self.Update = update
	
	self.Instance = script.Templat:Clone()
	self.Instance.Name = "Dropdown"

	local dock = parent:FindFirstAncestorOfClass("DockWidgetPluginGui"):: GuiObject

	local function updateProperties()
		local newProperties = properties()
		
		if newProperties then
			for propertie: string, value: any in newProperties do
				self.Instance[propertie] = value
			end
		end
		
		self.Instance.Visible = not not newProperties
		
		if self.Instance.Visible then
			local maxYSize = dock.AbsoluteSize.Y - self.Instance.AbsolutePosition.Y - 4
			
			local size = self.Instance.Size
			self.Instance.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, math.min(self.Instance.Container.AbsoluteCanvasSize.Y + 4, maxYSize))
		end
		
		if newProperties == false then
			self:Destroy()
		end
	end

	table.insert(self.Connections, dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateProperties))
	
	if content then
		self:LoadFromArray(self.Instance.Container, content)
	end
	
	local function destroy()
		self:Destroy()
	end
	
	table.insert(self.Connections, dock.WindowFocusReleased:Connect(destroy))
	
	table.insert(self.Connections, parent.InputBegan:Connect(function(input: InputObject)
		if not table.find({Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2}, input.UserInputType) then return end
		
		local absPos = self.Instance.AbsolutePosition
		local absSize = self.Instance.AbsoluteSize
		local pos = input.Position

		local inX = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X
		local inY = pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y

		if inX and inY then
			return
		end
		
		destroy()
	end))
	
	self.Instance.Parent = parent
	updateProperties()
	
	return self
end

return Dropdown
