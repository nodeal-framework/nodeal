--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local SearchController = {}

local plugin
local controllers

--// Private //--
local Root = script.Parent

local Resources = Root.Parent.Parent.Parent
local Modules = Resources.Modules

local Dropdown = require(Modules.Dropdown)
local PackagesHandler = require(Modules.PackagesHandler)

local success_GetSortOptions, SortOptions = PackagesHandler.GetSortOptions()

local default_header_datas = {
	Sorting = {
		Option = success_GetSortOptions and SortOptions.defaults.sortBy or "downloads",
		Order = success_GetSortOptions and SortOptions.defaults.sortOrder or "desc"
	}
}

local function _save_header_datas()
	plugin:SetSetting("Nodeal:Packages:Header", SearchController.HeaderDatas or default_header_datas)
end

local function _sort_id_to_display(id: string)
	for _, option in SortOptions.sorts do
		if option.id == id then
			return option.label
		end
	end
	
	return "None"
end

--// Public //--
SearchController.UpdateSignal = nil

function SearchController.GetInput()
	return SearchController.Input.Text
end

function SearchController.CancelSignal()
	if SearchController.UpdateSignal then
		task.cancel(SearchController.UpdateSignal)
	end

	SearchController.UpdateSignal = nil
end

function SearchController.Changed(instant: boolean)
	SearchController.CancelSignal()

	if controllers.PageController.CurrentPage == 1 then -- Browse
		SearchController.UpdateSignal = task.delay(instant and 0 or 0.3, controllers.BrowseController.Refresh)
	end
end

function SearchController.Build(_class, _controllers, _dock)
	plugin = _class.plugin
	controllers = _controllers
	
	SearchController.HeaderDatas = plugin:GetSetting("Nodeal:Packages:Header") or default_header_datas
	SearchController.HeaderDatas.Sorting = default_header_datas.Sorting
	
	SearchController.Input = _dock.Container.Header.Body.Search.Input
end

function SearchController.Init(_, _, _dock)
	SearchController.Input:GetPropertyChangedSignal("Text"):Connect(SearchController.Changed)
	
	_dock.Container.Header.Body.SortOption.Label.Text = _sort_id_to_display(SearchController.HeaderDatas.Sorting.Option)
	
	for _, button: ImageButton? in _dock.Container.Header.Body:GetChildren() do
		local behavior = button:FindFirstChild("Behavior")

		if not behavior or not button:IsA("ImageButton") then continue end
		behavior = require(behavior)
		
		behavior.SortOptions = SortOptions
	
		local promises = function()
			_dock.Container.Header.Body.SortOption.Label.Text = _sort_id_to_display(SearchController.HeaderDatas.Sorting.Option)
			return SearchController.Changed(true)
		end

		button.MouseButton1Click:Connect(function()
			Dropdown.new(_dock.Overlay, behavior.getProperties, behavior.getContent(SearchController.HeaderDatas, _save_header_datas), _dock.Container.Header, promises)
		end)
	end
	
	_dock.Container.Header.Body.SortOrder.MouseButton1Click:Connect(function()
		if SearchController.HeaderDatas.Sorting.Order == "desc" then
			SearchController.HeaderDatas.Sorting.Order = "asc"
			_dock.Container.Header.Body.SortOrder.Icon.Image = "rbxassetid://7072723932"
		else
			SearchController.HeaderDatas.Sorting.Order = "desc"
			_dock.Container.Header.Body.SortOrder.Icon.Image = "rbxassetid://7072723858"
		end
		
		SearchController.Changed(true)
	end)
end

return SearchController