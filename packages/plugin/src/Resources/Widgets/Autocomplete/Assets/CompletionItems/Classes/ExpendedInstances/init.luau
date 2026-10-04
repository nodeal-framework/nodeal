local ExpendedInstances = {}

-- Extand --
function ExpendedInstances:Extand(content: any?)
	if content then
		if typeof(content) == "table" then
			local result = script:GetChildren()
			
			for _, v in content do
				table.insert(result, v)
			end
			
			return result
		elseif typeof(content) == "Instance" then
			local result = script:GetChildren()
			
			table.insert(result, content)
			
			return result
		end
	end
end

return ExpendedInstances
