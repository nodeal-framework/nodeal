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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

type Set = { [Instance]: boolean }

local Packager = {}
Packager.__index = Packager

--// Registry //--

-- ServerStorage.Nodeal.Packages.<id> holds the installed version and one reference per installed instance.
local function ensure(parent: Instance, name: string, className: string): Instance
	local found = parent:FindFirstChild(name)

	if not found then
		found = Instance.new(className)
		found.Name, found.Parent = name, parent
	end

	return found
end

local function getRegistry(packageId: string): StringValue
	local nodeal = ensure(ServerStorage, "Nodeal", "RayValue")
	return ensure(ensure(nodeal, "Packages", "RayValue"), packageId, "StringValue") :: StringValue
end

local function installedVersion(packageId: string): string?
	local nodeal = ServerStorage:FindFirstChild("Nodeal")
	local packages = nodeal and nodeal:FindFirstChild("Packages")
	local registry = packages and packages:FindFirstChild(packageId)

	return registry and registry:IsA("StringValue") and registry.Value or nil
end

local function resolve(path: string): Instance?
	local current: Instance? = game

	for segment in path:gmatch("[^.]+") do
		current = current and current:FindFirstChild(segment)
	end

	return current ~= game and current or nil
end

-- A reference also remembers where its instance lives: an ObjectValue alone goes nil
-- as soon as the instance is cut, pasted or copied to another place.
local function track(instance: Instance, registry: Instance)
	local tracker = Instance.new("ObjectValue")
	tracker.Name, tracker.Value = instance.Name, instance
	tracker:SetAttribute("Path", instance:GetFullName())
	tracker.Parent = registry
end

-- A live reference refreshes its path; a dead one is relinked by it, or removed.
local function heal(registry: Instance)
	for _, tracker in registry:GetDescendants() do
		if not tracker:IsA("ObjectValue") then continue end

		local target = tracker.Value

		if target and target:IsDescendantOf(game) then
			tracker:SetAttribute("Path", target:GetFullName())
			continue
		end

		local path = tracker:GetAttribute("Path")
		local found = path and resolve(path)

		if found then
			tracker.Value = found
		else
			tracker:Destroy()
		end
	end
end

local function controlledSet(registry: Instance): Set
	local controlled = {}

	for _, tracker in registry:GetDescendants() do
		if tracker:IsA("ObjectValue") and tracker.Value then
			controlled[tracker.Value] = true
		end
	end

	return controlled
end

-- True when something under the instance was not installed by the package.
local function holdsUserContent(instance: Instance, controlled: Set): boolean
	for _, descendant in instance:GetDescendants() do
		if not controlled[descendant] then
			return true
		end
	end

	return false
end

--// Installing //--

-- Carries what the user owns from an instance into the one that replaces it.
local function merge(existing: Instance, incoming: Instance, controlled: Set)
	if not existing:IsA("LuaSourceContainer") then
		-- settings and tags given to a folder outlive the version
		for name, value in existing:GetAttributes() do
			incoming:SetAttribute(name, value)
		end

		for _, tag in existing:GetTags() do
			incoming:AddTag(tag)
		end
	end

	for _, child in existing:GetChildren() do
		local twin = incoming:FindFirstChild(child.Name)

		if twin and twin.ClassName == child.ClassName then
			merge(child, twin, controlled)
		elseif not controlled[child] or holdsUserContent(child, controlled) then
			child.Parent = incoming
		end
	end
end

-- The package's own files: the new one takes the place, the old one is parked in the backup.
local function replace(target: Instance, incoming: Instance, controlled: Set, backup: Instance)
	local existing = target:FindFirstChild(incoming.Name)

	if existing then
		-- a folder shipped over something else only brings its content
		if existing.ClassName ~= incoming.ClassName and incoming:IsA("Folder") then
			for _, child in incoming:GetChildren() do
				replace(existing, child, controlled, backup)
			end

			incoming:Destroy()
			return
		end

		merge(existing, incoming, controlled)
		existing.Parent = backup
	end

	incoming.Parent = target
end

-- A profile is starter content: it fills gaps, never touches what is already there,
-- and is the user's from then on (no reference is kept on it).
local function fill(target: Instance, incoming: Instance, present: Set)
	local existing = target:FindFirstChild(incoming.Name)

	if not existing then
		incoming.Parent = target
		return
	end

	present[existing] = true

	for _, child in incoming:GetChildren() do
		fill(existing, child, present)
	end

	incoming:Destroy()
end

-- Parked code must not run: no root tag for the loader, nothing for the plugin to index.
local function neutralize(backup: Instance, tagRoot: string)
	for _, descendant in backup:GetDescendants() do
		descendant:RemoveTag(tagRoot)

		if descendant:IsA("LuaSourceContainer") then
			descendant:SetAttribute("ContentExcluded", true)
		end
	end
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

--// Package //--

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

function Packager:GetId(): string
	local packageId = self.Root:GetAttribute("Package")
	assert(packageId ~= nil, "[Packager] Missing Package ID on " .. self.Root.Name)

	return tostring(packageId)
end

function Packager:GetVersions(): (string, string?)
	return self:GetManifest().Version or "unknown", installedVersion(self:GetId())
end

function Packager:GetStatus(): PackageStatus
	return Packager.CheckStatus(self:GetId(), (self:GetVersions()))
end

function Packager.CheckStatus(packageId: string, latestVersion: string): PackageStatus
	local installed = installedVersion(packageId)

	if not installed then
		return "none"
	end

	if installed ~= latestVersion then
		return "outdated"
	end

	return "latest"
end

-- Repairs the references of every installed package. Cheap: run it when the plugin starts.
function Packager.Heal()
	local nodeal = ServerStorage:FindFirstChild("Nodeal")
	local packages = nodeal and nodeal:FindFirstChild("Packages")
	if not packages then return end

	for _, registry in packages:GetChildren() do
		heal(registry)
	end
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

-- Removes what the package brought. A folder the user filled since then stays.
function Packager:Uninstall()
	local packageId = self:GetId()
	local registry = getRegistry(packageId)

	heal(registry)

	local controlled = controlledSet(registry)

	for instance in controlled do
		if instance.Parent and not holdsUserContent(instance, controlled) then
			instance:Destroy()
		end
	end

	registry:Destroy()

	ChangeHistoryService:SetWaypoint(`Uninstalled {packageId}`)
end

-- Installs over any version. Nothing is destroyed: the user's content follows the new version,
-- and what the package replaces or drops is parked in ServerStorage.Nodeal.Backups.<id>.
function Packager:Install(profileName: string?, variables: VariableMapping?)
	local packageId = self:GetId()
	local targetProfile = profileName or self:GetDefaultProfile()
	local mapping: VariableMapping = variables or {}

	local recording = ChangeHistoryService:TryBeginRecording(`Install {packageId}`)

	local success, message = xpcall(function()
		local sourceClone = self.Source:Clone()
		local placeholders = {}
		collectPlaceholders(sourceClone, placeholders)

		local firstStarter = #placeholders + 1
		local profileClone = nil

		if targetProfile and self.Profiles then
			local profile = self.Profiles:FindFirstChild(targetProfile)

			if profile then
				profileClone = profile:Clone()
				collectPlaceholders(profileClone, placeholders)
			end
		end

		-- refused here, before the place is touched
		for _, item in placeholders do
			if item.IsVariable then
				assert(mapping[item.VarName], string.format("[Packager] Missing mapping for variable <%s>", item.VarName))
			end
		end

		local registry = getRegistry(packageId)
		heal(registry)

		local controlled = controlledSet(registry)

		-- read before the manifest itself is replaced
		local global = ReplicatedStorage:FindFirstChild("Global")
		local manifest = global and global:FindFirstChild("Manifest")
		local tagRoot = manifest and manifest:GetAttribute("TagRoot") or "Nodeal.Root"

		local backups = ensure(registry.Parent.Parent, "Backups", "Folder")
		local former = backups:FindFirstChild(packageId)
		if former then former:Destroy() end

		local backup = Instance.new("Folder")
		backup.Name, backup.Parent = packageId, backups

		local shipped = {}
		local present: Set = {}

		for index, item in placeholders do
			local pathStr = mapping[item.VarName] or item.VarName

			if item.ParentPath then
				local fullPath = if item.ParentPath ~= "" then item.ParentPath .. "." .. pathStr else pathStr
				local target = resolvePath(game, fullPath)

				for _, content in item.Instance:GetChildren() do
					if index >= firstStarter then
						fill(target, content, present)
						continue
					end

					-- listed before the merge: afterwards it also holds what the user owns
					local descendants = content:GetDescendants()
					table.insert(shipped, content)
					table.move(descendants, 1, #descendants, #shipped + 1, shipped)

					replace(target, content, controlled, backup)
				end

				item.Instance:Destroy()
			end
		end

		sourceClone:Destroy()
		if profileClone then profileClone:Destroy() end

		-- what this version no longer ships is parked, unless the user keeps something in it
		local dropped = {}

		for instance in controlled do
			if instance:IsDescendantOf(game) and not instance:IsDescendantOf(backup) and not present[instance] and not holdsUserContent(instance, controlled) then
				dropped[instance] = true
			end
		end

		for instance in dropped do
			if not dropped[instance.Parent] then
				instance.Parent = backup
			end
		end

		neutralize(backup, tagRoot)

		if #backup:GetChildren() == 0 then
			backup:Destroy()
		end

		registry:ClearAllChildren()
		registry.Value = self:GetManifest().Version

		for _, instance in shipped do
			if instance:IsDescendantOf(game) then
				track(instance, registry)
			end
		end
	end, debug.traceback)

	if recording then
		-- a failed install is rolled back whole
		ChangeHistoryService:FinishRecording(recording, if success then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	end

	if not success then
		error(message, 0)
	end
end

function Packager:Destroy()
	if self.Root then
		self.Root:Destroy()
	end
	setmetatable(self, nil)
	table.clear(self)
end

return Packager
