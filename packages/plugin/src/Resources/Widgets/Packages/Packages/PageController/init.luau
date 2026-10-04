--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local PageController = {}

--// Private //--
local Root = script.Parent

--// Public //--
PageController.CurrentPage = 1

function PageController.JumpTo(index: number | string)
	if typeof(index) == "string" then
		local instance = PageController.Container:FindFirstChild(index)
		if not instance then return end

		index = instance.LayoutOrder
	end

	if typeof(index) ~= "number" and index ~= PageController.CurrentPage then return end

	PageController.CurrentPage = index
	PageController.PageLayout:JumpToIndex(index - 1)
	
	PageController.Update(index)
end

function PageController.Update(index: number)
	index = index or PageController.CurrentPage
	
	for _, page: GuiObject in PageController.Header:GetChildren() do
		if not page:IsA("ImageButton") then continue end
		
		local selected = page.LayoutOrder == index
		
		page.BackgroundTransparency = selected and 0 or 1
		page.BorderSizePixel = selected and 2 or 0
		
		page.UpperBorder.Visible = selected
		page.LowerBorder.Visible = not selected
	end
end

function PageController.Build(_, _, _dock: typeof(Root.Parent.Assets.Ui))
	PageController.Container = _dock.Container.Body.Container
	PageController.Header = _dock.Container.Header.Header
	PageController.PageLayout = PageController.Container.UIPageLayout
end

function PageController.Init(_, _, _)
	for _, page: GuiObject in PageController.Header:GetChildren() do
		if not page:IsA("ImageButton") then continue end

		page.Activated:Connect(function()
			PageController.JumpTo(page.LayoutOrder)
		end)
	end
	
	PageController.Update()
end

return PageController