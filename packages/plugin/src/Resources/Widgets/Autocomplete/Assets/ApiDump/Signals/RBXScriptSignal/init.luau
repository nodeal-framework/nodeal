return {
	["Name"] = script.Name,
	["Members"] = {
		{
			["Name"] = "Connect",
			["MemberType"] = "Function",
			["Parameters"] = {
				{
					["Name"] = "func",
					["Type"] = {
						["Name"] = "(...any) -> ()"
					}
				}
			},
			["ReturnType"] = {
				["Name"] = "RBXScriptConnection"
			}
		},
		{
			["Name"] = "Wait",
			["MemberType"] = "Function",
			["ReturnType"] = {
				["Name"] = "Tuple"
			}
		},
		{
			["Name"] = "Once",
			["MemberType"] = "Function",
			["Parameters"] = {
				{
					["Name"] = "func",
					["Type"] = {
						["Name"] = "(...any) -> ()"
					}
				}
			},
			["ReturnType"] = {
				["Name"] = "RBXScriptConnection"
			}
		},
		{
			["Name"] = "ConnectParallel",
			["MemberType"] = "Function",
			["Parameters"] = {
				{
					["Name"] = "func",
					["Type"] = {
						["Name"] = "(...any) -> ()"
					}
				}
			},
			["ReturnType"] = {
				["Name"] = "RBXScriptConnection"
			}
		}
	}
}