--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local ServerStorage = game:GetService("ServerStorage")
local SerializationService = game:GetService("SerializationService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

export type VariableMapping = { [string]: string }

export type PackageStatus = "none" | "outdated" | "latest"

export type Package = {
	Root: Folder,
	Source: (Folder | ModuleScript)?,
	Profiles: (Folder | ModuleScript)?,

	Export: (self: Package, instance: boolean?) -> string | Instance,
	GetVariables: (self: Package) -> { string },
	GetProfiles: (self: Package) -> { { Name: string, Variables: { string } } },
	GetManifest: (self: Package) -> { [string]: any },
	GetVersions: (self: Package) -> (string, string?),
	GetStatus: (self: Package) -> PackageStatus,
	Install: (self: Package, profileName: string?, variables: VariableMapping?) -> (),
	Uninstall: (self: Package) -> (),
	Destroy: (self: Package) -> (),
}

local Packager = {}
Packager.__index = Packager

local function getRegistry(packageId: string): StringValue
	local nodeal = ServerStorage:FindFirstChild("Nodeal") or Instance.new("RayValue")
	nodeal.Name, nodeal.Parent = "Nodeal", ServerStorage

	local packages = nodeal:FindFirstChild("Packages") or Instance.new("RayValue")
	packages.Name, packages.Parent = "Packages", nodeal

	local reg = packages:FindFirstChild(packageId) or Instance.new("StringValue")
	reg.Name, reg.Parent = packageId, packages

	return reg :: StringValue
end

local function findTracker(instance: Instance, registry: Instance): ObjectValue?
	for _, val in registry:GetChildren() do
		if val:IsA("ObjectValue") then
			if val.Value == instance then
				return val
			end

			local found = findTracker(instance, val)
			if found then return found end
		end
	end

	return nil
end

local function isControlled(instance: Instance, registry: Instance, oldRegistry: Instance?): boolean
	if findTracker(instance, registry) then return true end
	if oldRegistry and findTracker(instance, oldRegistry) then return true end
	return false
end

local function trackRecursive(instance: Instance, registry: Instance)
	local tracker = Instance.new("ObjectValue")
	tracker.Name, tracker.Value, tracker.Parent = instance.Name, instance, registry
	for _, child in instance:GetChildren() do
		trackRecursive(child, registry)
	end
end

local function smartMerge(existing: Instance, newInstance: Instance, registry: Instance, oldRegistry: Instance)
	for _, child in existing:GetChildren() do
		if isControlled(child, registry, oldRegistry) then
			local nextNew = newInstance:FindFirstChild(child.Name)

			if nextNew then
				smartMerge(child, nextNew, registry, oldRegistry)
			end
		else
			child.Parent = newInstance
		end
	end
end

local function smartInstall(target: Instance, newInstance: Instance, registry: Instance, oldRegistry: Instance)
	local name = newInstance.Name
	local existing = target:FindFirstChild(name)

	if existing then
		if existing.ClassName ~= newInstance.ClassName and newInstance:IsA("Folder") then
			for _, child in newInstance:GetChildren() do
				smartInstall(existing, child, registry, oldRegistry)
			end

			newInstance:Destroy()
			return
		end

		smartMerge(existing, newInstance, registry, oldRegistry)
		existing:Destroy()
	end

	newInstance.Parent = target
end

local function findVariables(root: Instance): { string }
	local vars, seen = {}, {}

	for _, child in root:GetDescendants() do
		local name = child.Name:match("^<(.+)>$")

		if name and not seen[name] then
			seen[name] = true
			table.insert(vars, name)
		end
	end

	return vars
end

local function getRelativePath(root: Instance, target: Instance): string?
	local segments = {}
	local current = target

	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end

	if current ~= root then return nil end
	return table.concat(segments, ".")
end

local function collectPlaceholders(root: Instance, list: { any })
	for _, child in root:GetChildren() do
		local varName = child.Name:match("^<(.+)>$")
		table.insert(list, { 
			Instance = child, 
			VarName = varName or child.Name, 
			IsVariable = varName ~= nil,
			Root = root,
			ParentPath = getRelativePath(root, child.Parent)
		})
	end

	for _, child in root:GetDescendants() do
		if child.Parent == root then continue end
		local varName = child.Name:match("^<(.+)>$")

		if varName then
			child.Name = varName
			table.insert(list, { 
				Instance = child, 
				VarName = varName, 
				IsVariable = true,
				Root = root,
				ParentPath = getRelativePath(root, child.Parent)
			})
		end
	end
end

local function executeBuild(module: ModuleScript, ...)
	local success, content = pcall(require, module)
	if not success then return end

	if typeof(content) == "table" and typeof(content.Build) == "function" then
		pcall(content.Build, ...)
	end

	return content
end

local function resolvePath(root: Instance, pathString: string): Instance
	local current = root

	for segment in pathString:gmatch("[^./]+") do
		local nextNode = current:FindFirstChild(segment)

		if not nextNode and current == game then
			local success, service = pcall(game.GetService, game, segment)
			if success then nextNode = service end
		end

		if not nextNode then
			nextNode = Instance.new("Folder")
			nextNode.Name, nextNode.Parent = segment, current
		end
		current = nextNode
	end

	return current
end

function Packager._init(rootFolder: Folder): Package
	local self = setmetatable({}, Packager)

	self.Root = rootFolder
	self.Source = rootFolder:FindFirstChild("Source") :: (Folder | ModuleScript)?
	self.Profiles = rootFolder:FindFirstChild("Profiles") :: (Folder | ModuleScript)?
	assert(self.Source, "[Packager] Missing Source")

	return (self :: any) :: Package
end

function Packager.fromFolder(rootFolder: Folder): Package
	return Packager._init(rootFolder)
end

function Packager.fromData(data: string): Package
	local buf = buffer.fromstring(data)

	local success, instances = pcall(function()
		return SerializationService:DeserializeInstancesAsync(buf)
	end)

	if not success or #instances == 0 then
		error("[Packager] Deserialization failure: " .. tostring(instances))
	end

	return Packager._init(instances[1] :: Folder)
end

function Packager:GetVariables(): { string }
	return findVariables(self.Source)
end

function Packager:GetDefaultProfile(): string?
	if self.Profiles then
		for _, profile in self.Profiles:GetChildren() do
			local attr = profile:GetAttribute("Default")

			if attr == true then
				return profile.Name
			end
		end
	end

	return nil
end

function Packager:GetProfiles(): { { Name: string, Variables: { string } } }
	local list = {}

	if self.Profiles then
		for _, child in self.Profiles:GetChildren() do
			table.insert(list, {
				Name = child.Name,
				Variables = findVariables(child)
			})
		end
	end

	return list
end

function Packager:GetManifest(): { [string]: any }
	local manifest = { Name = self.Root.Name, Version = "unknown", Variables = {} }

	for key, value in pairs(self.Root:GetAttributes()) do
		manifest[key] = value
	end

	return manifest
end

function Packager:GetVersions(): (string, string?)
	local currentVersion = self:GetManifest().Version or "unknown"

	local packageId = self.Root:GetAttribute("Package")
	assert(packageId ~= nil, "[Packager] Missing Package ID on " .. self.Root.Name)
	packageId = tostring(packageId)

	local nodeal = ServerStorage:FindFirstChild("Nodeal")
	local packages = nodeal and nodeal:FindFirstChild("Packages")
	local reg = packages and packages:FindFirstChild(packageId)

	local installedVersion = reg and reg:IsA("StringValue") and reg.Value or nil

	return currentVersion, installedVersion
end

function Packager:GetStatus(): PackageStatus
	local current, installed = self:GetVersions()

	if not installed then
		return "none"
	end

	if installed ~= current then
		return "outdated"
	end

	return "latest"
end

function Packager.CheckStatus(packageId: string, latestVersion: string): PackageStatus
	local nodeal = ServerStorage:FindFirstChild("Nodeal")
	local packages = nodeal and nodeal:FindFirstChild("Packages")
	local reg = packages and packages:FindFirstChild(packageId)

	local installedVersion = reg and reg:IsA("StringValue") and reg.Value or nil

	if not installedVersion then
		return "none"
	end

	if installedVersion ~= latestVersion then
		return "outdated"
	end

	return "latest"
end

function Packager:Export(instance: boolean?): string | Instance
	local exportClone = self.Root:Clone()
	local sourceClone = exportClone:FindFirstChild("Source")
	local profilesClone = exportClone:FindFirstChild("Profiles")

	if sourceClone and sourceClone:IsA("ModuleScript") then
		executeBuild(sourceClone)
	end

	if profilesClone then
		if profilesClone:IsA("ModuleScript") then
			executeBuild(profilesClone)
		end

		for _, child in profilesClone:GetChildren() do
			if child:IsA("ModuleScript") then
				executeBuild(child)
			end
		end
	end

	local success, serialized

	if not instance then
		success, serialized = pcall(function()
			return SerializationService:SerializeInstancesAsync({ exportClone })
		end)

		exportClone:Destroy()
	end

	if not instance and not success then error("[Packager] Export failure: " .. tostring(serialized)) end
	return instance and exportClone or buffer.tostring(serialized)
end

function Packager:Uninstall()
	local packageId = self.Root:GetAttribute("Package")
	assert(packageId ~= nil, "[Packager] Missing Package ID on " .. self.Root.Name)
	packageId = tostring(packageId)

	local registry = getRegistry(packageId)

	for _, tracker in registry:GetChildren() do
		if tracker:IsA("ObjectValue") and tracker.Value then
			tracker.Value:Destroy()
		end
	end

	registry:Destroy()

	ChangeHistoryService:SetWaypoint(`Uninstalled {packageId}`)
end

function Packager:Install(profileName: string?, variables: VariableMapping?)
	local packageId = self.Root:GetAttribute("Package")
	assert(packageId ~= nil, "[Packager] Missing Package ID on " .. self.Root.Name)
	packageId = tostring(packageId)

	local targetProfile = profileName or self:GetDefaultProfile()
	local mapping: VariableMapping = variables or {}
	local registry = getRegistry(packageId)
	registry.Value = self:GetManifest().Version

	local oldRegistry = Instance.new("Folder")
	for _, child in registry:GetChildren() do
		child.Parent = oldRegistry
	end

	local sourceClone = self.Source:Clone()
	local placeholders = {}
	collectPlaceholders(sourceClone, placeholders)

	if targetProfile and self.Profiles then
		local profile = self.Profiles:FindFirstChild(targetProfile)

		if profile then
			local profileClone = profile:Clone()
			collectPlaceholders(profileClone, placeholders)
		end
	end

	for _, item in placeholders do
		local pathStr = mapping[item.VarName]

		if item.IsVariable then
			assert(pathStr, string.format("[Packager] Missing mapping for variable <%s>", item.VarName))
		else
			pathStr = pathStr or item.VarName
		end

		if item.ParentPath then
			local fullPath = if item.ParentPath ~= "" then item.ParentPath .. "." .. pathStr else pathStr
			local target = resolvePath(game, fullPath)

			for _, content in item.Instance:GetChildren() do
				trackRecursive(content, registry)
				smartInstall(target, content, registry, oldRegistry)
			end
			item.Instance:Destroy()
		end
	end

	sourceClone:Destroy()

	for _, tracker in oldRegistry:GetChildren() do
		if tracker:IsA("ObjectValue") then
			local oldInstance = tracker.Value

			if oldInstance and oldInstance.Parent then
				if not (oldInstance:IsA("Folder") and #oldInstance:GetChildren() > 0) then
					oldInstance:Destroy()
				end
			end
		end
	end
	oldRegistry:Destroy()

	ChangeHistoryService:SetWaypoint(`Installed {packageId}`)
end

function Packager:Destroy()
	if self.Root then
		self.Root:Destroy()
	end
	setmetatable(self, nil)
	table.clear(self)
end

return Packager