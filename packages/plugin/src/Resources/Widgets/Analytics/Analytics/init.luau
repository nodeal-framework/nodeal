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

-- Modules --

-- Variables --

-- Functions --
local function dockResizeUpdate()
	local container = dock.Container
end

-- Callback --
local Analytics = {}

function Analytics.Init(self: any, widget: string)
	class = self
	plugin = class.plugin

	local widget = self.widgets[widget]
	dock = widget.dock
	
	--ScriptEditorService.TextDocumentDidOpen:Connect(function(edited)
	--	for _, script: ModuleScript in ScriptEditorService:GetScriptDocuments() do
	--		--print(script:GetFullName())
	--	end
	--end)

	--ScriptEditorService.TextDocumentDidClose:Connect(function(edited)
	--	for _, script: ModuleScript in ScriptEditorService:GetScriptDocuments() do
	--		--print(script:GetFullName())
	--	end
	--end)
	
	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(dockResizeUpdate)
	dockResizeUpdate()
end

return Analytics
