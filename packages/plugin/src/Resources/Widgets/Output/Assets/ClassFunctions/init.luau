-- Constants --
local studio = settings():GetService("Studio")

-- Modules --
local highlight = require(script.Parent.Highlighter).run

-- Functions --
local function getColor(enum: EnumItem, modifier: EnumItem): Color3
	return "#"..studio.Theme:GetColor(enum, modifier or "Default"):ToHex()
end

local function stripPrefix(str: string, prefix: string): string?
	if string.sub(str, 1, #prefix) == prefix then
		return string.sub(str, #prefix + 1)
	else
		return
	end
end

-- Methodes --
local methodes = {}

methodes["string"] = function(arg: string): {}
	local callback = {
		text = arg,
	}
	
	local result = stripPrefix(arg, ".luau:")
	if result then
		callback.text = result
		callback.display = highlight(result)
		
		callback.background = script.ScriptBackground
	end
	
	return callback
end

methodes["boolean"] = function(arg: boolean): {}
	local callback = {
		text = `{tostring(arg)} `,
		sufix = "</stroke>",
		color = getColor(Enum.StudioStyleGuideColor.ScriptBool)
	}
	
	callback.prefix = `<stroke color="{callback.color}" thickness="0.4">`
	
	return callback
end

methodes["number"] = function(arg: number): {}
	local callback = {
		text = tostring(arg),
		color = getColor(Enum.StudioStyleGuideColor.ScriptNumber)
	}
	
	return callback
end

methodes["EnumItem"] = function(arg: EnumItem): {}
	local callback = {
		text = tostring(arg),
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}

	callback.display = highlight(callback.text)

	return callback
end

methodes["CFrame"] = function(arg: CFrame): {}
	local pos = arg.Position
	local rx, ry, rz = arg:ToEulerAnglesXYZ()

	local callback = {
		text = `CFrame.new({pos.X}, {pos.Y}, {pos.Z}) * CFrame.Angles({rx}, {ry}, {rz})`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}

	callback.display = highlight(callback.text)

	return callback
end

methodes["Color3"] = function(arg: Color3): {}
	local callback = {
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}
	
	local rounded = {
		R = math.round(arg.R*255),
		G = math.round(arg.G*255),
		B = math.round(arg.B*255)
	}
	
	callback.text = `■ Color3.new({rounded.R}, {rounded.G}, {rounded.B})`
	
	local primary = highlight(`_ Color3.new({rounded.R}, {rounded.G}, {rounded.B})`)
	
	local replacements = {
		`<font color="{`#{arg:ToHex()}`}">■</font>`
	}
	
	local index = 0
	local result = string.gsub(primary, "_", function()
		index += 1
		local value = replacements[index]
		return value or "_"
	end)
	
	callback.display = result

	return callback
end

methodes["Vector3"] = function(arg: Vector3): {}
	local callback = {
		text = `Vector3.new({arg.X}, {arg.Y}, {arg.Z})`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}
	
	callback.display = highlight(callback.text)
	
	return callback
end

methodes["Vector2"] = function(arg: Vector2): {}
	local callback = {
		text = `Vector2.new({arg.X}, {arg.Y})`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}
	
	callback.display = highlight(callback.text)
	
	return callback
end

methodes["UDim2"] = function(arg: UDim2): {}
	local callback = {
		text = `UDim2.new({arg.X.Scale}, {arg.X.Offset}, {arg.Y.Scale}, {arg.Y.Offset})`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}

	callback.display = highlight(callback.text)

	return callback
end

methodes["UDim"] = function(arg: UDim): {}
	local callback = {
		text = `UDim.new({arg.Scale}, {arg.Offset})`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}

	callback.display = highlight(callback.text)

	return callback
end

methodes["Instance"] = function(arg: Instance): {}
	local callback = {
		text = `game.{arg:GetFullName()}`,
		color = getColor(Enum.StudioStyleGuideColor.ScriptBuiltInFunction)
	}
	
	callback.display = highlight(callback.text)
	
	return callback
end

-- Callback --
return methodes
