--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local BrowseController = {}

local controllers

--// Private //--
local Root = script.Parent

local Resources = Root.Parent.Parent.Parent
local Modules = Resources.Modules

local PackagesHandler = require(Modules.PackagesHandler)

local Assets = Root.Parent.Assets
local Templates = Assets.Templates

local TimeThresholds = {
	{ name = "year", value = 31536000 },
	{ name = "month", value = 2592000 },
	{ name = "day", value = 86400 },
	{ name = "hour", value = 3600 },
	{ name = "minute", value = 60 }
}

local function _get_relative_time(iso: string): (string, boolean)
	local parsedDate = DateTime.fromIsoDate(iso)

	if not parsedDate then
		return "Invalid date", false
	end

	local currentTimestamp = DateTime.now().UnixTimestamp
	local targetTimestamp = parsedDate.UnixTimestamp

	local isFuture = targetTimestamp > currentTimestamp

	local secondsDiff = math.abs(targetTimestamp - currentTimestamp)

	for _, threshold in TimeThresholds do
		local amount = math.floor(secondsDiff / threshold.value)

		if amount >= 1 then
			local plural = amount > 1 and "s" or ""
			return amount .. " " .. threshold.name .. plural, isFuture
		end
	end

	local plural = secondsDiff > 1 and "s" or ""
	return secondsDiff .. " second" .. plural, isFuture
end

--// Public //--
BrowseController.PER_PAGE = 25
BrowseController.LOAD_PADDING = 100  * 3

BrowseController.CurrentPage = 1

BrowseController.HasMore = true
BrowseController.Fetching = false

function BrowseController.Refresh()
	BrowseController.Fetching = false
	
	BrowseController.ClearPages()
	BrowseController.LoadNextPage()
end

function BrowseController.ClearPages()
	for _, instance: GuiObject in BrowseController.Container:GetChildren() do
		if not instance:IsA("ImageButton") then continue end 

		instance:Destroy()
	end

	BrowseController.CurrentPage = 1
	BrowseController.HasMore = true
end

function BrowseController.LoadPackage(package: any)
	local root = Templates.Package:Clone()

	root.Name = package.id

	local header = root.Header

	if package.iconId and #package.iconId > 0 then
		header.IconSection.Icon.Image = `rbxthumb://type=Asset&id={package.iconId}&w=150&h=150`
	else
		header.IconSection:Destroy()
	end

	header.NameSection.PackageName.Text = package.name or package.id

	if package.creators then
		local creators = "by"

		for index: number, creator: any in package.creators do
			if not creator.user or not creator.user.username then continue end

			creators = `{creators}{index == 1 and "" or ","} {creator.user.username}`
		end

		if creators == "by" then
			creators = "by unknown"
		end

		header.NameSection.PackageCreators.Text = creators
	end

	if package.tags and #package.tags > 0 then
		for _, tag: any in package.tags do
			local instance = Templates.Tag:Clone()

			instance.TagText.Text = tag.name

			instance.Parent = root.TagsRow
		end
	else
		root.TagsRow:Destroy()
	end

	if package.description then
		root.Description.Text = package.description
	else
		root.Description:Destroy()
	end

	local bottom = root.BottomRow
	bottom.Downloads.Value.Text = package.downloads or 0
	bottom.Likes.Value.Text = package._count and package._count.interactions or 0

	if package.versions then
		local current = package.versions[1]

		if current then
			root.BottomRow.Updated.VersionBadge.VersionText.Text = current.version or "v?.?.?"

			local release, future = _get_relative_time(current.publishedAt)
			if release then
				root.BottomRow.Updated.LastUpdate.Text = future and `Update in {release}` or `Updated {release} ago`
			
				root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					root.BottomRow.Updated.LastUpdate.TextTransparency = root.BottomRow.Updated.LastUpdate.AbsolutePosition.X > root.BottomRow.Updated.AbsolutePosition.X and 0 or 1
				end)
			else
				root.BottomRow.Updated.LastUpdate:Destroy()
			end
		else
			root.BottomRow.Updated:Destroy()
		end
	end

	root.Parent = BrowseController.Container
end

function BrowseController.LoadNextPage(searchQuery: string?): any?
	if not BrowseController.HasMore and not BrowseController.Fetching then return end

	BrowseController.Fetching = true

	if not searchQuery then
		searchQuery = controllers.SearchController.GetInput()
	end

	local success, result = PackagesHandler.GetPackages(
		searchQuery,
		BrowseController.CurrentPage,
		BrowseController.PER_PAGE,
		controllers.SearchController.HeaderDatas.Sorting.Option,
		controllers.SearchController.HeaderDatas.Sorting.Order
	)

	if not success then
		warn("Package BrowseController API Error :", result.error)
		return
	end

	if not BrowseController.Fetching then return end

	for _, package in result.packages do
		BrowseController.LoadPackage(package)
	end

	if result.pagination then
		BrowseController.HasMore = BrowseController.CurrentPage < result.pagination.totalPages
		BrowseController.CurrentPage += 1
	else
		BrowseController.HasMore = false
	end
	
	BrowseController.Fetching = false
	
	return result
end

function BrowseController.Update()
	local canvasSize = BrowseController.Container.AbsoluteCanvasSize.Y
	local windowSize = BrowseController.Container.AbsoluteWindowSize.Y
	local currentPos = BrowseController.Container.CanvasPosition.Y

	local bottom = (canvasSize - windowSize) - currentPos
	
	if bottom <= BrowseController.LOAD_PADDING then
		BrowseController.LoadNextPage()
	end
end

function BrowseController.Build(_, _controllers, _dock)
	controllers = _controllers
	
	BrowseController.Container = _dock.Container.Body.Container.Browse
	BrowseController.Container:GetPropertyChangedSignal("CanvasPosition"):Connect(BrowseController.Update)
end

function BrowseController.Init(_, _, _)
	BrowseController.LoadNextPage()
end

return BrowseController