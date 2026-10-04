local Behavior = {}

local Button = script.Parent

local constantSize = (2 * 5) + (2 * 26)

function Behavior.getProperties()
	if not Button.Visible then return end

	local result = {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 40)
	}

	local filtersVisible = false
	result.Size = UDim2.new(filtersVisible and 1 or 0, filtersVisible and 1 or 0, 0, 0)

	return result
end

return Behavior
