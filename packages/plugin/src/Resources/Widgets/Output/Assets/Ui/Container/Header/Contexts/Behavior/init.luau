local Behavior = {}

local Header = script.Parent.Parent

local Button = Header.Contexts

local constantSize = (1 * 5) + (2 * 108)

local canAllUpdate = true

local function UpdateAll(instance)
	local all = true

	for _, child in instance.Parent:GetChildren() do
		if child.Name ~= "Toggle" or not all or child.Toggled.Value then continue end

		all = false
	end
	
	canAllUpdate = false
	instance.Parent.Parent.Parent.Toggle.Toggled.Value = all
	task.delay(0.1, function()
		canAllUpdate = true
	end)
end

function Behavior.getContent(datas: {}, save: () -> ())
	return {
		{
			Type = "Toggle",
			Label = "All",
			Function = function(value: boolean, instance: ImageButton)
				if not canAllUpdate then return end
				
				for _, child in instance.Parent.Container.Body:GetChildren() do
					if child.Name ~= "Toggle" then continue end
					
					child.Toggled.Value = value
				end
			end,
		},
		{
			Type = "Container",
			Label = "Contexts",
			Childs = {
				{
					Type = "Toggle",
					Label = "Internal",
					Default = datas.Contexts.internal,
					Function = function(value: boolean, instance: ImageButton)
						datas.Contexts.internal = value
						
						UpdateAll(instance)
						save()
					end,
				},
				{
					Type = "Toggle",
					Label = "Server",
					Default = datas.Contexts.server,
					Function = function(value: boolean, instance: ImageButton)
						datas.Contexts.server = value
						
						UpdateAll(instance)
						save()
					end,
				},
				{
					Type = "Toggle",
					Label = "Client",
					Default = datas.Contexts.client,
					Function = function(value: boolean, instance: ImageButton)
						datas.Contexts.client = value
						
						UpdateAll(instance)
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
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 4, 0, 40)
	}
	
	result.Size = UDim2.new(0, constantSize, 0, 0)
	
	return result
end

return Behavior
