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
local runService = game:GetService("RunService")

-- Constants --
local pluginFolder = script.Parent.Parent

local pluginName = pluginFolder:GetAttribute("Name")

local Resources = pluginFolder.Resources

-- Modules --

-- Variables --
_G.CanNodealLoop = false
_G.Nodeal = {}

local plugins = {}
plugins.__index = plugins

-- Functions --
return function(plugin)
	local self = setmetatable({}, plugins)

	self.playTest = runService:IsRunning()
	
	self.client = runService:IsClient()
	self.server = runService:IsServer()

	self.context = self.client and "client" or "server"

	self.plugin = plugin
	self.toolbar = self.plugin:CreateToolbar(pluginName)

	self.disabled = {}
	self.widgets = {}
	
	for _, module in Resources.Modules:GetChildren() do
		if module:GetAttribute("Excluded") then continue end
		
		local content = require(module)
		
		if type(content) == "table" and content.Init then
			content.Init(self)
		end
	end

	return self
end
