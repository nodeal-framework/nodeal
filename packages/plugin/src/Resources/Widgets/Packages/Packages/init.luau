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

-- Services --
local ScriptEditorService = game:GetService("ScriptEditorService")

-- Types --

-- Constants --
local plugin: plugin
local class

local dock: typeof(script.Parent.Assets.Ui)

local resources = script.Parent.Parent.Parent
local modules = resources.Modules

local Assets = script.Parent.Assets

-- Modules --
local Packager = require(modules.Packager)

--// Private //--
local Templates = Assets.Templates

local Controllers = {}
for _, controller in script:GetChildren() do
	if not controller:IsA("ModuleScript") then continue end
	Controllers[controller.Name] = require(controller)
end

local function dockResizeUpdate()
	local container = dock.Container
end

--// Public //--
local Packages = {}

function Packages.Init(self: any, widget: string)
	class = self
	plugin = class.plugin

	local widget = self.widgets[widget]
	dock = widget.dock
	
	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(dockResizeUpdate)
	dockResizeUpdate()
	
	for _, controller in Controllers do
		if not controller.Build then continue end
		controller.Build(self, Controllers, dock)
	end
	
	for _, controller in Controllers do
		if not controller.Init then continue end
		controller.Init(self, Controllers, dock)
	end
end

return Packages
