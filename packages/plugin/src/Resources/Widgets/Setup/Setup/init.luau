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
local debugId = nil
local __NODEAL_PACKAGE_ID__ = "nodeal-framework"

local installedIcon = "rbxassetid://7072721134"

-- Services --
local RunService = game:GetService("RunService")

-- Types --

-- Constants --
local plugin: plugin
local plugin_widget: {}

local version_menu

local resources = script.Parent.Parent.Parent
local modules = resources.Modules

local widgets = script.Parent.Parent

local ifSetup = {
	{widgets.Account, true and not RunService:IsRunning()},
	{widgets.Explorer, true and not RunService:IsRunning()},
	{widgets.Output, false},
	{widgets.Packages, true and not RunService:IsRunning()},
	{widgets.Analytics, false and not RunService:IsRunning()},
	{widgets.Autocomplete, true and not RunService:IsRunning()}
}

-- Modules --
local Packager = require(modules.Packager)
local PackagesHandler = require(modules.PackagesHandler)

-- Variables --
local versions: { any }? = nil
local last_version: string? = nil

-- Read from the place, so nothing waits for the site: "none" or "outdated" until the versions arrive.
local nodeal_status = Packager.CheckStatus(__NODEAL_PACKAGE_ID__, "")

--// Private //--
local function EnableWidgets()
	for index: number, widgetFolder: { Folder & boolean } in ifSetup do
		if not widgetFolder[2] or (debugId and debugId ~= index) then continue end
		widgetFolder[1]:SetAttribute("Disabled", false)
	end
end

local function MountVersionsMenu()
	if not versions then return end

	for index: number, version_storage: any in versions do
		version_menu:AddNewAction(version_storage.version, version_storage.version)

		if index == 1 then
			version_menu:AddSeparator()
		end
	end
end

-- Yields on the site. Answers false when it could not be reached.
local function FetchVersions(): boolean
	local success, result = PackagesHandler.GetVersions(__NODEAL_PACKAGE_ID__)

	if not success or type(result.versions) ~= "table" or versions then
		return versions ~= nil
	end

	versions = result.versions
	last_version = versions[1] and versions[1].version

	if last_version then
		nodeal_status = Packager.CheckStatus(__NODEAL_PACKAGE_ID__, last_version)
	end

	MountVersionsMenu()
	return true
end

local function AskForVersion(): string?
	local action = version_menu:ShowAsync()
	if not action then return end

	return action.Text
end

--// Public //--
local Setup = {}

function Setup.Clicked(self: any, widgetName: string)
	local widget = self.widgets[widgetName]

	if not versions and not FetchVersions() then
		warn("[Nodeal] nodeal.dev could not be reached: no version to install.")
		return
	end

	if nodeal_status == "latest" then
		widget.button.Enabled = false
		return
	end

	local requested_version = AskForVersion()
	if not requested_version then return end

	local success, content = PackagesHandler.DownloadVersion(__NODEAL_PACKAGE_ID__, requested_version)
	if not success then
		warn(`[Nodeal] {requested_version} could not be downloaded:`, content)
		return
	end

	widget.button.Enabled = false

	local installed, message = pcall(function()
		local package = Packager.fromData(content)
		package:Install()
		package:Destroy()
	end)

	if not installed then
		warn(`[Nodeal] {requested_version} could not be installed. Anything it replaced is in ServerStorage.Nodeal.Backups:\n{message}`)
		widget.button.Enabled = true
		return
	end

	plugin_widget.button.Icon = installedIcon

	nodeal_status = Packager.CheckStatus(__NODEAL_PACKAGE_ID__, last_version)
	widget.button.Enabled = nodeal_status ~= "latest"

	warn("For the best Nodeal experience, please manually disable ‘UseNewLuauTypeSolver’ in your Workspace properties.")
	EnableWidgets()
end

function Setup.Init(self: any, widget: string)
	plugin = self.plugin
	plugin_widget = self.widgets[widget]

	if RunService:IsRunning() then
		EnableWidgets()
		return
	end

	version_menu = plugin:CreatePluginMenu("Nodeal:Setup:Version", "Version Selection")

	Packager.Heal()

	if nodeal_status ~= "none" then
		plugin_widget.defaultIcon = installedIcon
		EnableWidgets()
	end

	-- The button is settled once the site answers; the windows do not wait for it.
	task.spawn(function()
		if FetchVersions() and nodeal_status == "latest" then
			plugin_widget.disabledButton = true

			if plugin_widget.button then
				plugin_widget.button.Enabled = false
			end
		end
	end)
end

return Setup
