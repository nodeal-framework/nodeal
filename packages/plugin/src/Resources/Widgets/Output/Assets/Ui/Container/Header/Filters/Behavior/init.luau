local Behavior = {}

local Header = script.Parent.Parent
local Button = Header.Filters

local MessagesBehavior = require(Header.Messages.Behavior)
local ContextsBehavior = require(Header.Contexts.Behavior)

function Behavior.getContent(datas: {}, save: () -> ())
	return {
		{
			Type = "Container",
			Label = "Message Types",
			Childs = MessagesBehavior.getContent(datas, save)
		},
		{
			Type = "Container",
			Label = "Context Types",
			Childs = ContextsBehavior.getContent(datas, save)
		}
	}
end

function Behavior.getProperties()
	if not Button.Visible then return end
	
	return {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.new(1, -8, 0, 0)
	}
end

return Behavior
