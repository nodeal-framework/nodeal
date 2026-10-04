return {
	["Name"] = script.Name,
	["Members"] = {
		{
			["Name"] = "Lerp",
			["MemberType"] = "Function",
			["Parameters"] = {
				{
					["Name"] = "goal",
					["Type"] = {
						["Name"] = script.Name
					}
				},
				{
					["Name"] = "alpha",
					["Type"] = {
						["Name"] = "float"
					}
				}
			},
			["ReturnType"] = {
				["Name"] = script.Name
			}
		},
		
		{
			["Name"] = "X",
			["MemberType"] = "Property",
			["ValueType"] = {
				["Name"] = "Udim"
			}
		},
		{
			["Name"] = "Y",
			["MemberType"] = "Property",
			["ValueType"] = {
				["Name"] = "Udim"
			}
		},
		{
			["Name"] = "Width",
			["MemberType"] = "Property",
			["ValueType"] = {
				["Name"] = "Udim"
			}
		},
		{
			["Name"] = "Height",
			["MemberType"] = "Property",
			["ValueType"] = {
				["Name"] = "Udim"
			}
		}
	}
}