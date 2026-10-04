local Behavior = {}

local Header = script.Parent.Parent
local Search = Header.Search

local Button = Header.Settings

local constantSize = (2 * 5) + (2 * 26)

function Behavior.getContent(datas: {}, save: () -> ())
	return {
		{
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
	}
end

function Behavior.getProperties()
	if not Button.Visible then return end
	
	local result = {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 40)
	}

	local filtersVisible = Header.Filters.Visible
	result.Size = UDim2.new(filtersVisible and 1 or 0, filtersVisible and -8 or constantSize + Search.AbsoluteSize.X, 0, 0)
	
	return result
end

return Behavior
