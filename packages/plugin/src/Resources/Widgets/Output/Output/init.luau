--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

-- Configuration --
local contextColors = {
	client = Color3.fromRGB(52, 154, 213),
	server = Color3.fromRGB(0, 204, 103),

	internal = Color3.fromRGB(173, 63, 203),
	plugin = Color3.fromRGB(255, 204, 0)
}

local levelColors = {
	[1] = Color3.fromRGB(50, 200, 50),
	[2] = Color3.fromRGB(255, 115, 21),
	[3] = Color3.fromRGB(200, 50, 50)
}

-- Services --
local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Types --

-- Constants --
local Resources = script.Parent.Parent.Parent
local Modules = Resources.Modules

local Dropdown = require(Modules.Dropdown)

--
local Global = ReplicatedStorage:WaitForChild("Global", 5)

local plugin: plugin
local class

local assets = script.Parent.Assets
local StudioOutputTransmitter = assets.SignalTransmitter

local messageTemplate = assets.MessageTemplate

local modules = script.Parent.Parent.Parent.Modules

-- Tweens --
local loadingStyle = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Modules --
local classFunctions = require(assets.ClassFunctions)
local SearchModule = require(assets.SearchModule)

local Dropdown = require(modules.Dropdown)

-- Variables --
local dock: DockWidgetPluginGui & typeof(script.Parent.Assets.Ui)

local logs = {}

local headerDatas
local defaultHeaderDatas = {
	Settings = {
		Search = {
			TakeCaps = false
		}
	},
	Contexts = {
		internal = true,
		server = true,
		client = true
	},
	Messages = {
		error = true,
		warning = true,
		log = true
	}
}

-- Functions --
local function saveHeaderDatas()
	plugin:SetSetting("Nodeal:Output:Header", headerDatas or defaultHeaderDatas)
end

local function setupHeader()
	for _, button: ImageButton? in dock.Container.Header:GetChildren() do
		local behavior = button:FindFirstChild("Behavior")

		if not behavior or not button:IsA("ImageButton") then continue end
		behavior = require(behavior)

		button.MouseButton1Click:Connect(function()
			Dropdown.new(dock.Popup, behavior.getProperties, behavior.getContent(headerDatas, saveHeaderDatas), dock.Container.Header, SearchChanged)
		end)
	end
end

function getTagged(tag: string): { Instance? }
	local instances = CollectionService:GetTagged(tag)

	for _, instance in instances do
		if instance:IsDescendantOf(dock) then continue end

		local index = table.find(instances, instance)
		table.remove(instances, index)
	end

	return instances
end

local function getCurrentTimeOfDay(dateTable: table, tickInfo: number): string
	local hours = dateTable.hour or 0
	local minutes = dateTable.min or 0
	local seconds = dateTable.sec or 0
	local milliseconds = math.floor((tickInfo % 1) * 1000)

	return string.format("%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
end

function findMultiplier(input: number, target: number): number
	if input == 0 then
		return 0
	end

	return target / input
end

local loadingAsset = assets.Loading
local loadings = {}

-- for i = 1, 3 do task.spawn(function() for y = 0, 3 do _G.Nodeal.Loading({}, i, y/3) task.wait(0.5) end end) end
function _G.Nodeal.Loading(cache: { [any]: any }, name: string, percent: number)
	percent = math.clamp(percent, 0, 1)

	local loadingGui: typeof(loadingAsset) = loadings[name] or loadingAsset:Clone()
	local firstload = loadings[name] == nil

	local finalSize = UDim2.fromScale(percent, 1)
	local finalPosition = UDim2.fromScale(findMultiplier(percent, 0.5), 0.5)

	if not loadingGui then return end

	loadingGui.Bar.Fill.Size = finalSize
	loadingGui.Bar.Fill.BackgroundTitle.Position = finalPosition

	-- TweenService:Create(loadingGui.Bar.Fill, loadingStyle, {Size = finalSize}):Play()
	-- TweenService:Create(loadingGui.Bar.Fill.BackgroundTitle, loadingStyle, {Position = finalPosition}):Play()

	loadingGui.Info.Text = string.format("%.1f%%", percent * 100)

	if firstload then
		loadingGui.Name = name

		loadingGui.Bar.HeightgroundTitle.Text = name
		loadingGui.Bar.Fill.BackgroundTitle.Text = name

		loadings[name] = loadingGui
		loadingGui.Parent = dock.Container.Footer
	end

	if percent == 1 then
		task.delay(1, function()
			if not loadingGui or not loadingGui.Parent or loadingGui.Bar.Fill.Size.X.Scale ~= 1 then return end

			loadings[name] = nil
			loadingGui:Destroy()
		end)
	end
end

function _G.Nodeal.Print(cache: table, ...: any?)
	local messageFrame = getTagged("Message.Frame")[1] :: ScrollingFrame

	local message = messageTemplate:Clone()

	local timeString = getCurrentTimeOfDay(cache.receptionTimestamp or os.date("*t"), cache.receptionTick or tick())

	message.Time.Text = timeString

	if cache.context and contextColors[cache.context] then
		local contextColor = contextColors[cache.context]
		message.Context.BackgroundColor3 = contextColor
	end

	message:SetAttribute("context", cache.context or "")

	local decodedMessage = {}
	for _, arg: any in {...} do
		local argType = typeof(arg)
		local callback = classFunctions[argType] and classFunctions[argType](arg) or {text = tostring(arg)}

		table.insert(decodedMessage, callback)
	end

	local totalString = ""
	local richString = ""

	for index: number, arg: { [string]: any } in decodedMessage do
		totalString = totalString..arg.text..(arg.sufix and "" or " ")
		richString = richString ..
			(arg.color and '<font color="'..arg.color..'">' or "") ..
			(arg.prefix or "") ..
			(arg.display or arg.text) ..
			(arg.sufix or " ") ..
			(arg.color and '</font>' or "")

		if arg.background then
			arg.background:Clone().Parent = message.Container.Label
		end
	end

	message.Name = `{timeString}: {totalString}`
	message:SetAttribute("RealText", totalString)

	message.Container.Clipboard.Text = totalString
	message.Container.Label.Text = richString

	message.Container.Label.TextColor3 = levelColors[cache.level] or Color3.fromRGB(204, 204, 204)

	local isAtBottom = messageFrame.AbsoluteCanvasSize.Y - messageFrame.AbsoluteSize.Y == messageFrame.CanvasPosition.Y
	message.Parent = messageFrame

	if isAtBottom then
		messageFrame.CanvasPosition = Vector2.new(0, messageFrame.AbsoluteCanvasSize.Y + messageFrame.AbsoluteSize.Y)
	end
end

function inject_tracker(self: any)
	local StudioOutputSignal: BindableEvent

	if self.client then
		StudioOutputTransmitter = Global:WaitForChild("SignalTransmitter", 5)
		StudioOutputSignal = Global:WaitForChild("StudioOutputSignal", 5)

		StudioOutputSignal.Event:Once(function()
			StudioOutputSignal.Parent = nil
			StudioOutputTransmitter.Parent = nil

			StudioOutputSignal.Event:Connect(function(methode: string, header: table, ...: any?)
				_G.Nodeal[methode](header, ...)
			end)

			StudioOutputSignal:SetAttribute("LoadedClient", true)
		end)

		StudioOutputTransmitter.OnClientEvent:Connect(function(methode: string, header: table, ...: any?): any?
			_G.Nodeal[methode](header, ...)
		end)

		StudioOutputTransmitter:FireServer()
	elseif self.server then
		StudioOutputTransmitter.Parent = Global

		StudioOutputSignal = Instance.new("BindableEvent")
		StudioOutputSignal.Name = "StudioOutputSignal"
		StudioOutputSignal.Parent = Global

		local OutputTransmitterLoaded = false

		StudioOutputSignal.Event:Once(function()
			StudioOutputSignal.Event:Connect(function(...: any?)
				repeat task.wait() until OutputTransmitterLoaded
				StudioOutputTransmitter:FireAllClients(...)
			end)

			StudioOutputSignal:SetAttribute("LoadedServer", true)
		end)

		StudioOutputTransmitter.OnServerEvent:Once(function()
			OutputTransmitterLoaded = true
		end)
	end
end

function SearchChanged()
	local instances = SearchModule:GetSortedListFromInstanceChildren(
		dock.Container.Body.MessageFrame,
		"Frame", "RealText",
		dock.Container.Header.Search.Input.Text,
		false, headerDatas.Settings.Search.TakeCaps, true
	)

	for _, instance: GuiObject in dock.Container.Body.MessageFrame:GetChildren() do
		if not instance:IsA("Frame") then continue end

		local visible = (not not table.find(instances, instance)) or dock.Container.Header.Search.Input.Text == ""

		local attributes = instance:GetAttributes()

		if headerDatas.Contexts[attributes.context] ~= nil and not headerDatas.Contexts[attributes.context] then
			visible = false
		end

		instance.Visible = visible
	end
end

local function dockResizeUpdate()
	local container = dock.Container
	local header = container.Header

	local filtersVisible = dock.AbsoluteSize.X > 575
	local searchVisible = dock.AbsoluteSize.X > 170

	header.Separator.Visible = filtersVisible

	header.Messages.Visible = filtersVisible
	header.Contexts.Visible = filtersVisible

	header.Filters.Visible = not filtersVisible

	header.Search.Visible = searchVisible

	if searchVisible then
		header.Search.Size = UDim2.new(0, filtersVisible and 275 or 0, 1, 0)
		header.Search.UIFlexItem.FlexMode = filtersVisible and Enum.UIFlexMode.None or Enum.UIFlexMode.Fill
	end
end

-- Callback --
local Output = {}

function Output.Init(self: any, widget: string)
	class = self
	plugin = class.plugin

	headerDatas = plugin:GetSetting("Nodeal:Output:Header") or defaultHeaderDatas

	local widget = self.widgets[widget]
	dock = widget.dock

	local connections = {}

	if self.playTest then
		inject_tracker(self)
	else
		--table.insert(connections, RunService.Heartbeat:Connect(function()

		--end))
	end

	dock.Container.Header.Clear.MouseButton1Click:Connect(function()
		for _, instance: GuiObject in dock.Container.Body.MessageFrame:GetChildren() do
			if not instance:IsA("Frame") then continue end

			instance:Destroy()
		end
	end)

	dock.Destroying:Once(function()
		for _, connection: RBXScriptConnection in connections do
			connection:Disconnect()
		end
	end)

	dock.Container.Header.Search.Input:GetPropertyChangedSignal("Text"):Connect(SearchChanged)
	dock.Container.Body.MessageFrame.ChildAdded:Connect(SearchChanged)

	setupHeader()

	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(dockResizeUpdate)
	dockResizeUpdate()
end

return Output