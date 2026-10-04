local Behavior = {}

local Header = script.Parent.Parent.Parent
local Search = Header.Search

local constantSize = (2 * 5) + (2 * 26)

function Behavior.getProperties(): { [string]: any }
	if not Search.Visible then return end
	
	local result = {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 40)
	}
	
	local filtersVisible = Header.Filters.Visible
	result.Size = UDim2.new(filtersVisible and 1 or 0, filtersVisible and -8 or constantSize + Search.AbsoluteSize.X, 0, 0)
	
	return result
end

return Behavior
