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

-- Services --
local RunService = game:GetService("RunService")

-- Types --

-- Constants --
local plugin: plugin
local plugin_widget: {}

local version_menu
local version_menu_list = {}

local resources = script.Parent.Parent.Parent
local modules = resources.Modules

local widgets = script.Parent.Parent
local assets = script.Parent.Assets

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
local success, setup_versions = PackagesHandler.GetVersions(__NODEAL_PACKAGE_ID__)

local versions = success and setup_versions.versions
local last_version = versions and versions[1] and versions[1].version

local nodeal_status = last_version and Packager.CheckStatus(__NODEAL_PACKAGE_ID__, last_version) or "outdated"



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

local function AskForVersion(): string?
	local action = version_menu:ShowAsync()
	if not action then return end
	
	return action.Text
end

--// Public //--
local Setup = {}

function Setup.Clicked(self: any, widget: string)
	local widget = self.widgets[widget]

	if nodeal_status == "latest" then
		widget.button.Enabled = false
		return
	end
	
	local requested_version = AskForVersion()
	if not requested_version then return end
	
	local success, content = PackagesHandler.DownloadVersion(__NODEAL_PACKAGE_ID__, requested_version)
	if not success then warn(success, content) end

	widget.button.Enabled = false
	plugin_widget.button.Icon = "rbxassetid://7072721134"
	
	local package = Packager.fromData(content)
	package:Install()
	package:Destroy()
	
	if requested_version ~= last_version then
		widget.button.Enabled = true
	end
	
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
	MountVersionsMenu()
	
	if nodeal_status == "none" then
		return
	else
		plugin_widget.defaultIcon = "rbxassetid://7072721134"
		
		if nodeal_status == "latest" then
			plugin_widget.disabledButton = true
		end
	end
	
	EnableWidgets()
end

return Setup