local Behavior = {}

local Header = script.Parent.Parent.Parent
local Search = Header.Search

function Behavior.getProperties(): { [string]: any }
	if not Search.Visible then return end
	
	return {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 85),
		Size = UDim2.new(1, -8, 0, 0)
	}
end

return Behavior
