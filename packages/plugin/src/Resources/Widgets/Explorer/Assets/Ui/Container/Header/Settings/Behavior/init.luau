local Behavior = {}

local Header = script.Parent.Parent
local Search = Header.Search

local Button = Header.Settings

function Behavior.getContent(datas: {}, save: () -> ())
	local result = {}
	
	local search = {
		Type = "Container",
		Label = "Search",
		Childs = {
			{
				Type = "Toggle",
				Label = "Caps Considered",
				Default = datas.Settings.Search.TakeCaps,
				Function = function(value: boolean)
					datas.Settings.Search.TakeCaps = value
					save()
				end,
			}
		}
	}
	
	table.insert(result, search)
	
	local displayed = {
		Type = "Container",
		Label = "Displayed",
		Childs = {}
	}
	
	local instances = {}
	for _, instance: Frame in script.Parent.Parent.Parent.Body.InstancesFrame:GetChildren() do
		if not instance:IsA("Frame") then continue end
		
		table.insert(instances, instance)
	end
	
	table.sort(instances, function(a: Frame, b: Frame): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	
	for _, instance: Frame in instances do
		local attributes = instance:GetAttributes()
		local id = attributes.ExplorerAlias or instance.Name

		if datas.Settings.Displayed[id] == nil then
			datas.Settings.Displayed[id] = true
		end

		table.insert(displayed.Childs, {
			Type = "Toggle",
			Label = id,
			Default = datas.Settings.Displayed[id],
			Function = function(value: boolean)
				datas.Settings.Displayed[id] = value
				save()
			end,
		})
	end
	
	table.insert(result, displayed)
	
	return result
end

function Behavior.getProperties()
	if not Button.Visible then return end
	
	return {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 40),
		Size = UDim2.new(1, -8, 0, 0)
	}
end

return Behavior
