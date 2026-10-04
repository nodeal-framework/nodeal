--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local UploadController = {}

local controllers

--// Private //--
local Root = script.Parent

local Resources = Root.Parent.Parent.Parent
local Modules = Resources.Modules

local Packager = require(Modules.Packager)
local PackagesHandler = require(Modules.PackagesHandler)

local Assets = Root.Parent.Assets
local Templates = Assets.Templates

--// Public //--
function UploadController.Build(_, _controllers, _dock)
	controllers = _controllers
	
	UploadController.Container = _dock.Container.Body.Container.Upload
end

function UploadController.Init(plug, _, _)
	UploadController.Container.Package.MouseButton1Click:Connect(function()
		local selected = game:GetService("Selection"):Get()[1]

		local package = Packager.fromFolder(selected)
		local exported = package:Export(true)
		
		exported.Parent = workspace
		game:GetService("Selection"):Set({exported})
		
		local saved = plug.plugin:PromptSaveSelectionAsync(selected.Name)

		exported:Destroy()
	end)
end

return UploadController