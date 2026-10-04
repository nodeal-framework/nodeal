--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local instancesDisplays = {
	["ModuleScript"] = {
		icon = "http://www.roblox.com/asset/?id=131615904655406",
		color = Color3.new(1, 1, 1)
	},
	--["Folder"] = {
	--	icon = "rbxassetid://9940330336",
	--	color = Color3.new(1, 1, 1)
	--},
}

local unknownDisplay = {
	icon = "rbxassetid://4034148680",
	color = Color3.new(1, 1, 1)
}

-- Services --
local selection = game:GetService("Selection")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local StudioService = game:GetService("StudioService")
local userInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local scriptEditorService = game:GetService("ScriptEditorService")

-- Types --

-- Constants --
local widget = script.Parent
local assets = widget.Assets

local class: {}
local plugin: plugin

local dock: typeof(assets.Ui)

local Resources = script.Parent.Parent.Parent
local Modules = Resources.Modules

local Dropdown = require(Modules.Dropdown)

-- Modules --
local SearchModule = require(assets.SearchModule)

local utils = require(Resources.Modules.Utils)

local headerDatas
local defaultHeaderDatas = {
	Settings = {
		Search = {
			TakeCaps = false
		},
		Displayed = {}
	}
}

-- Variables --
local function saveHeaderDatas()
	plugin:SetSetting("Nodeal:Explorer:Header", headerDatas or defaultHeaderDatas)
	SearchChanged()
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

local function getInstanceFromPath(origin: Instance, path: string): Instance?
	for part in string.gmatch(path, "[^%.]+") do
		origin = origin:FindFirstChild(part)
		if not origin then
			return nil
		end
	end
	return origin
end

local function requestInfos(title: string, options: {}): {}?
	local connections = {}
	
	local input = dock.Input
	local container = input.Container
	
	for _, child: GuiObject in container:GetChildren() do
		if child.Name ~= "temp" then continue end
		
		child:Destroy()
	end
	
	container.Title.Text = title
	
	local templates = container.UIListLayout
	
	local optionsUis = {}
	for index: number, option: { type: string, name: string, placeholder: any, value: any } in options do
		local box = templates[option.type]:Clone() :: GuiObject
		local attributes = box:GetAttributes()
		
		box.Name = "temp"
		
		local nameInstance = getInstanceFromPath(box, attributes.namePath)
		nameInstance[attributes["nameProperty"]] = option.name
		
		if option.placeholder then
			local nameInstance = getInstanceFromPath(box, attributes.placeholderPath)
			nameInstance[attributes["placeholderProperty"]] = option.placeholder
		end
		
		local valueInstance = getInstanceFromPath(box, attributes.path)
		if option.value and option.value ~= "" then
			valueInstance[attributes["property"]] = option.value
		end
		
		box.Parent = container
		
		table.insert(optionsUis, {
			name = option.name,
			instance = valueInstance,
			property = attributes["property"],
			ui = box,
			needed = not option.value
		})
	end
	
	local clicked = false
	local ended = false
	
	local conclusion = container.Conclusion
	
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 1, true)
	
	table.insert(connections, conclusion.Confirm.MouseButton1Click:Connect(function()
		local missing = false
		
		for _, info: { needed: boolean, ui: GuiObject, instance: GuiObject, property: string } in optionsUis do
			if not info.needed then continue end
			local attributes = info.ui:GetAttributes()
			
			if info.instance[info.property] == "" then
				missing = true
				
				local warningInstance = getInstanceFromPath(info.ui, attributes["warningPath"])
				if not warningInstance then return end
				
				local properties = {}
				properties[attributes["warningProperty"]] = Color3.fromRGB(255, 75, 75)
				
				tweenService:Create(warningInstance, tweenInfo, properties):Play()
			end
		end
		
		if missing then
			return
		end
		
		clicked = true
	end))
	
	table.insert(connections, conclusion.Cancel.MouseButton1Click:Connect(function()
		ended = true
	end))
	
	table.insert(connections, input.InputEnded:Connect(function(input: InputObject)
		if not table.find({Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2}, input.UserInputType) then return end
		
		local absPos = container.AbsolutePosition
		local absSize = container.AbsoluteSize
		local pos = input.Position
		
		local inX = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X
		local inY = pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
		
		if inX and inY then
			return
		end
		
		ended = true
	end))
	
	input.Visible = true
	
	repeat task.wait() until clicked or ended
	input.Visible = false
	
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end
	
	if ended then
		return
	end
	
	local result = {}
	
	for _, info: { name: string, instance: GuiObject, property: string } in optionsUis do
		result[info.name] = info.instance[info.property]
	end
	
	return result
end

local functionsForTargets = {
	{ -- New Script
		getInfos = function(...)
			return {
				name = "New Script",
				icon = "rbxassetid://7072716346",
				order = 1
			}
		end,

		execution = function(...)
			local args = {...}
			
			local options = requestInfos("New Module", {
				{
					type = "string",
					name = "Name"
				}
			})
			
			if not options then return end
			
			local newScript = assets.ModuleTemplate:Clone()
			
			newScript.Name = options.Name
			newScript.Source = string.gsub(newScript.Source, "___ModuleName___", options.Name)
			
			newScript.Parent = args[1]
			return newScript
		end
	},
	
	{ -- New Folder
		getInfos = function(...)
			return {
				name = "New Folder",
				icon = "rbxassetid://7072716655",
				order = 2
			}
		end,

		execution = function(...)
			local args = {...}
			
			local options = requestInfos("New Folder", {
				{
					type = "string",
					name = "Name"
				}
			})

			if not options then return end
			
			local newFolder = Instance.new("Folder")
			
			newFolder.Name = options.Name
			
			newFolder.Parent = args[1]
			return newFolder
		end
	},
	
	---------------------------------------------
	
	--{ -- Toggle
	--	getInfos = function(...)
	--		local args = {...}
			
	--		if #args == 1 and not args[1]:IsA("ModuleScript") then
	--			return
	--		end
			
	--		local result = {
	--			order = 25
	--		}
			
	--		if #args > 1 then
	--			result.name = "Disable / Enable"
	--			result.icon = "rbxassetid://7072706576"
	--		else
	--			local disabled = args[1]:GetAttribute("_disabled")
				
	--			result.name = disabled and "Enable" or "Disable"
	--			result.icon = disabled and "rbxassetid://7072706576" or "rbxassetid://7072725299"
	--		end
			
	--		return result
	--	end,

	--	execution = function(...)
	--		local args = {...}
			
	--		if not args[1]:IsA("ModuleScript") then
	--			return
	--		end
			
	--		local state = args[1]:GetAttribute("_disabled")
	--		args[1]:SetAttribute("_disabled", not state)
	--	end
	--},
	
	--{ -- Set Id
	--	getInfos = function(...)
	--		local args = {...}
	--		if #args > 1 or not args[1]:IsA("ModuleScript") then
	--			return
	--		end
			
	--		return {
	--			name = "Set Id",
	--			icon = "rbxassetid://7072715920",
	--			order = 26
	--		}
	--	end,

	--	execution = function(...)
	--		local args = {...}
			
	--		local options = requestInfos("Set Id", {
	--			{
	--				type = "string",
	--				name = `Id`,
	--				placeholder = `Id (e.g. {args[1].Name})`,
	--				value = ""
	--			}
	--		})
			
	--		if not options then return end
			
	--		args[1]:SetAttribute("_id", options.Id)
	--	end
	--},
	
	---------------------------------------------
	
	{ -- Destroy
		getInfos = function(...)
			local args = {...}
			
			if #args > 1 then
				return
			end
			
			return {
				name = "Destroy",
				icon = "rbxassetid://7072723727",
				order = 50
			}
		end,

		execution = function(...)
			local args = {...}
			
			local options = requestInfos("Confirmation", {
				{
					type = "string",
					name = "Name",
					placeholder = args[1].Name
				}
			})
			
			if not options or options.Name ~= args[1].Name then return end
			
			args[1]:Destroy()
		end
	}
}

local pressedKeys = {}
local lastInstanceClick = {}

-- Functions --
function setParentVisible(frame: Frame)
	local parent = frame.Parent.Parent.Parent
	local id = parent:GetAttribute("ExplorerAlias") or parent.Name
	
	if headerDatas.Settings.Displayed[id] == false then return end
	if parent:GetAttribute("Root") then return end
	
	parent.Visible = true
	setParentVisible(parent)
end

function showInstances(instances: { [number]: Instance }?)
	local tagged = getTagged("Selectable")
	
	if instances then
		local visibles = {}
		
		for _, frame: Frame in tagged do
			local container = frame:FindFirstChild("Container")
			local header = container and container:FindFirstChild("Header")
			local link = header and header:FindFirstChild("Link")
			local instance = link and link.Value
			
			if not instance then
				frame.Visible = false
				continue
			end

			local index = table.find(instances, instance)
			
			local id = instance:GetAttribute("ExplorerAlias") or instance.Name
			frame.Visible = headerDatas.Settings.Displayed[id] ~= false and (index ~= nil)
			
			if frame.Visible then
				table.insert(visibles, frame)
			end
		end
		
		for _, visible: Frame in visibles do
			setParentVisible(visible)
		end
	else
		for _, frame: Frame in tagged do
			local id = frame:GetAttribute("ExplorerAlias") or frame.Name
			
			if headerDatas.Settings.Displayed[id] == false then continue end
			frame.Visible = true
		end
	end
end

function getTagged(tag: string): { Instance? }
	local instances = collectionService:GetTagged(tag)

	for _, instance in instances do
		if instance:IsDescendantOf(dock) then continue end

		local index = table.find(instances, instance)
		table.remove(instances, index)
	end

	return instances
end

function isInUnivers(instance: Instance): boolean?
	local roots = collectionService:GetTagged(utils.manifest.TagRoot)

	for _, root: Instance in roots do
		if instance == root or instance:IsDescendantOf(root) then
			return true
		end
	end
end

function updateSelection(instance: Instance, secondary: boolean?)
	local selected = selection:Get()
	local index = table.find(selected, instance)
	
	if table.find(pressedKeys, Enum.KeyCode.LeftControl) or (secondary and index) then
		if secondary or not index then
			if not index then
				table.insert(selected, instance)
				selection:Set(selected)
			end
		elseif index then
			table.remove(selected, index)
			selection:Set(selected)
		end
	else
		selection:Set({instance})
	end
end

function setExplorerSelection()
	local selected = selection:Get()
	local selectableTree = getTagged("Selectable")
	
	for _, frame: Frame in selectableTree do
		if table.find(selected, frame.Container.Header.Link.Value) then
			frame.Container.Header.BackgroundTransparency = 0
		else
			frame.Container.Header.BackgroundTransparency = 1
		end
	end
end

function updateFunctionsTab()
	local scrollingFrame = dock.FunctionsFrame.Container.ScrollingFrame
	local selected = selection:Get()
	
	for _, child: GuiObject in scrollingFrame:GetChildren() do
		if child.Name ~= "temp" then continue end
		
		child:Destroy()
	end
	
	local lastIndex = 0
	for _, button: ImageButton in scrollingFrame:GetChildren() do
		if not button:IsA("ImageButton") then continue end
		
		local index = button:GetAttribute("id")
		local func = functionsForTargets[index]
		
		local infos = func.getInfos(unpack(selected))
		
		if not infos then
			button.Visible = false
			continue
		end
		
		if infos.order - lastIndex > 1 then
			local divider = scrollingFrame.UIListLayout.Divider:Clone()

			divider.Name = "temp"
			divider.LayoutOrder = infos.order - 1

			divider.Parent = scrollingFrame
		end
		
		lastIndex = infos.order
		
		button.Visible = true
		
		button.Title.Text = infos.name
		button.Icon.Image = infos.icon
		button.LayoutOrder = infos.order
	end
end

function loadFunctionsTab()
	for index: number, func: { [string]: any } in functionsForTargets do
		local newButton = assets.FunctionTemplate:Clone()
		newButton:SetAttribute("id", index)
		
		newButton.MouseButton1Click:Connect(function()
			closeFunctionsTab()
			
			local selected = selection:Get()
			
			local callbacks = {}
			for _, instance: Instance in selected do
				if not isInUnivers(instance) then continue end
				
				local callback = func.execution(instance)
				
				if callback then
					table.insert(callbacks, callback)
				end
			end
			
			local finalSelection = {}
			
			for _, instance: Instance in callbacks do
				if typeof(instance) ~= "Instance" then continue end
				
				table.insert(finalSelection, instance)
			end
			
			if #finalSelection > 0 then
				selection:Set(finalSelection)
			end
		end)
		
		newButton.MouseEnter:Connect(function()
			newButton.BackgroundTransparency = 0
		end)
		
		newButton.MouseLeave:Connect(function()
			newButton.BackgroundTransparency = 1
		end)
		
		newButton.Parent = dock.FunctionsFrame.Container.ScrollingFrame
	end
end

function closeFunctionsTab()
	dock.Backclicked.Visible = false
	dock.FunctionsFrame.Visible = false
end

function openFunctionsTab()
	if runService:IsRunning() then return end
	
	updateFunctionsTab()
	
	local mousePosition = dock:GetRelativeMousePosition()
	dock.FunctionsFrame.Position = UDim2.fromOffset(mousePosition.x, mousePosition.y)

	local frameSize = dock.FunctionsFrame.AbsoluteSize
	local dockSize = dock.AbsoluteSize - Vector2.new(11, 0)
	
	local posX = mousePosition.x
	local posY = mousePosition.y

	if posX + frameSize.X > dockSize.X then
		posX = dockSize.X - frameSize.X
	end

	if posY - frameSize.Y < 0 then
		posY = frameSize.Y
	end

	posX = math.max(posX, 0)
	posY = math.min(posY, dockSize.Y)

	dock.FunctionsFrame.Position = UDim2.fromOffset(posX, posY)

	dock.FunctionsFrame.Visible = true
	dock.Backclicked.Visible = true
end

function childUpdated(frame: Frame, instance: Instance, parent: Frame)
	newChild(instance, parent)
	
	frame:Destroy()
end

local function getDisplayForInstance(instance)
	if instancesDisplays[instance.ClassName] then
		return instancesDisplays[instance.ClassName]
	end
	
	for className: string, display: {} in pairs(instancesDisplays) do
		if instance:IsA(className) then
			return display
		end
	end
	
	local official_icon = StudioService:GetClassIcon(instance.ClassName)
	if official_icon then
		return {
			icon = official_icon.Image,
			color = Color3.new(1, 1, 1)
		}
	end

	return unknownDisplay
end

function updateExpandHierarchy(body: Frame?): ()
	if not body then return end
	
	local arrow = body.Parent.Header.Arrow
	
	for _, child: Frame in body:GetChildren() do
		if child:IsA("Frame") and child.Container.Visible then
			local attributes = child:GetAttributes()
			
			arrow.Interactable = true
			arrow.Icon.Visible = true
			
			if attributes["ExplorerUnified"] then
				arrow.Interactable = false
				arrow.Icon.Visible = false
			end
			
			return
		end
	end
	
	arrow.Interactable = false
	arrow.Icon.Visible = false
end

function newChild(instance: Instance, parent: Frame?): Frame
	local attributes = instance:GetAttributes()
	
	local frame = assets.InstanceTemplate:Clone()
	frame:SetAttribute("ExplorerAlias", attributes.ExplorerAlias)
	
	frame.Container.Header.Arrow.Icon.Rotation = 180
	
	-- TODO: May be cool to add a config to still display the ContentExcluded (he look to be sad).
	if attributes["ExplorerExcluded"] or attributes["ContentExcluded"] then
		frame.Container.Visible = false
	end
	
	if attributes["ExplorerUnified"] then
		frame.Container.Body.Visible = false
	end
	
	frame.Container.Header.Link.Value = instance
	frame.Name = instance.Name
	
	frame.LayoutOrder = attributes["ExplorerOrder"] or 0
	frame.Container.Header.Label.Text = attributes["ExplorerAlias"] or instance.Name
	
	local instanceInfos = getDisplayForInstance(instance)
	
	local icon = frame.Container.Header.Icon
	icon.Image = attributes["ExplorerIcon"] or instanceInfos.icon
	icon.ImageColor3 = attributes["ExplorerColor"] or instanceInfos.color
	
	if instance:IsA("ModuleScript") then
		local context = utils.module.get_context(instance)
		
		if not (table.find(context, "client") or table.find(context, "server")) then
			icon.Size = UDim2.fromScale(0.8, 0.8)
			icon.ImageTransparency = 0.5
		end
		
		icon.Server.Visible = table.find(context, "server")
		icon.Client.Visible = table.find(context, "client")
	end
	
	frame.Division.BackgroundColor3 = attributes["ExplorerColor"] or instanceInfos.color
	
	if not parent then
		frame.Division.Visible = true
		frame.Container.Header.Arrow.LayoutOrder = 2
	end
	
	local connections = {}
	
	local function updated()
		for _, connection: RBXScriptConnection in connections do
			connection:Disconnect()
		end
		
		childUpdated(frame, instance, parent)
		setExplorerSelection()
	end
	
	table.insert(connections, frame.Container.Header.MouseEnter:Connect(function()
		if runService:IsRunning() then return end
		frame.Container.Header.New.Visible = true
	end))
	
	table.insert(connections, frame.Container.Header.MouseLeave:Connect(function()
		if runService:IsRunning() then return end
		frame.Container.Header.New.Visible = false
	end))
	
	
	
	table.insert(connections, frame.Container.Header.MouseButton1Click:Connect(function()
		if lastInstanceClick.instance == instance and lastInstanceClick.instant > tick() then
			if instance:IsA("ModuleScript") then
				scriptEditorService:OpenScriptDocumentAsync(lastInstanceClick.instance)
			end
		end
		
		lastInstanceClick = {instance = instance, instant = tick() + 0.25}
		updateSelection(instance)
	end))
	
	table.insert(connections, frame.Container.Header.MouseButton2Click:Connect(function()
		updateSelection(instance, true)
		openFunctionsTab()
	end))
	
	
	
	table.insert(connections, frame.Container.Header.New.MouseButton1Click:Connect(function()
		functionsForTargets[1].execution(instance)
	end))
	
	
	
	table.insert(connections, instance.ChildAdded:Connect(function(child: Instance)
		newChild(child, frame.Container.Body)
	end))
	
	table.insert(connections, instance:GetPropertyChangedSignal("Name"):Connect(updated))
	table.insert(connections, instance.AttributeChanged:Connect(updated))
	
	table.insert(connections, instance.AncestryChanged:Connect(function()
		frame:Destroy()
	end))
	
	table.insert(connections, instance.Destroying:Connect(function()
		frame:Destroy()
	end))
	
	frame.Destroying:Once(function()
		for _, connection: RBXScriptConnection in connections do
			connection:Disconnect()
		end
	end)
	
	loadFromArray(instance:GetChildren(), frame.Container.Body)
	
	frame.Parent = parent or dock.Container.Body.InstancesFrame
	
	-- updateExpandHierarchy(parent) -- < Could be cool
	
	requestSearch()
	
	return frame
end

function loadFromArray(array: { Instance? }, parent: Frame?)
	for _, instance: Instance in array do
		if instance:IsDescendantOf(workspace) then continue end
		
		newChild(instance, parent)
	end
end

local function loadRoots()
	local map = collectionService:GetTagged(utils.manifest.TagRoot)
	
	collectionService:GetInstanceAddedSignal(utils.manifest.TagRoot):Connect(function(instance: Instance)
		newChild(instance)
	end)
	
	loadFromArray(map)
end

local function getDescendants(array: { Instance }): { Instance }
	local result = {}
	
	for _, instance: Instance in array do
		table.insert(result, instance)

		for _, descendant in instance:GetDescendants() do
			table.insert(result, descendant)
		end
	end
	
	return result
end

-- Une seule passe de filtre par vague de noeuds. Elle etait rejouee a chaque enfant cree, et
-- newChild descend l'arbre en recursif : au chargement de la place, 313 noeuds x 67 ms de tri,
-- soit les vingt secondes de Studio fige que Roblox signalait en LuaHangedScript.
searchPending = false

function requestSearch()
	if searchPending then return end
	searchPending = true
	
	task.defer(function()
		searchPending = false
		SearchChanged()
	end)
end

function SearchChanged()
	if not dock:FindFirstChild("Container") then return end
	local text = dock.Container.Header.Search.Input.Text
	
	--if text == "" then
	--	showInstances()
	--	return
	--end
	
	local roots = collectionService:GetTagged(utils.manifest.TagRoot)
	local descendants = getDescendants(roots)
	
	local result = SearchModule:GetSortedListFromInstanceTable(
		descendants, 
		"Instance", 
		"Name", 
		text, 
		false,
		headerDatas.Settings.Search.TakeCaps, 
		true
	)
	
	showInstances(result)
end

local function dockResizeUpdate()
	local container = dock.Container
	local header = container.Header
	
	local searchVisible = dock.AbsoluteSize.X > 108
	
	header.Search.Visible = searchVisible
end

-- Callback --
local explorer = {}

function explorer.Init(self: any, widget: string)
	class = self
	plugin = class.plugin

	headerDatas = plugin:GetSetting("Nodeal:Explorer:Header") or defaultHeaderDatas
	
	local widget = self.widgets[widget]
	dock = widget.dock
	
	loadRoots()

	dock.Backclicked.MouseButton1Click:Connect(closeFunctionsTab)
	dock.Backclicked.MouseButton2Click:Connect(closeFunctionsTab)
	
	loadFunctionsTab()
	
	selection.SelectionChanged:Connect(setExplorerSelection)
	
	dock.InputSensor.InputBegan:Connect(function(input: InputObject)
		local index = table.find(pressedKeys, input.KeyCode)
		
		if not index then
			table.insert(pressedKeys, input.KeyCode)
		end
	end)
	
	dock.InputSensor.InputEnded:Connect(function(input: InputObject)
		local index = table.find(pressedKeys, input.KeyCode)

		if index then
			table.remove(pressedKeys, index)
		end
	end)
	
	local connections = {}
	
	table.insert(connections, userInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			closeFunctionsTab()
		end
	end))
	
	dock.Destroying:Once(function()
		for _, connection: RBXScriptConnection in connections do
			connection:Disconnect()
		end
	end)
	
	dock.Container.Header.Search.Input:GetPropertyChangedSignal("Text"):Connect(SearchChanged)
	
	setupHeader()
	
	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(dockResizeUpdate)
	dockResizeUpdate()
	
	SearchChanged()
end

return explorer