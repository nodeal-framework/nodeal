local Behavior = {}

local Button = script.Parent

function Behavior.getContent(datas: {}, save: () -> ())
	local result = {}
	
	for _, option in Behavior.SortOptions.sorts do
		table.insert(result, {
			Type = "Button",
			Label = option.label,
			Function = function()
				datas.Sorting.Option = option.id
				save()
				
				return true
			end
		})
	end
	
	return result
end

function Behavior.getProperties()
	if not Button.Visible then return end
	
	local width = 125
	
	return {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(Button.AbsolutePosition.X + Button.AbsoluteSize.X / 2, 85),
		Size = UDim2.fromOffset(width, 0)
	}
end

return Behavior
