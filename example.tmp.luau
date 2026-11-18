--[[
	Custom Function Comments - Arctic_Vibes 2025
]]
--!native
local ScriptEditorService = game:GetService("ScriptEditorService")																																																																																																																																																																																																																																											if plugin.Name ~= "cloud_118937729102831" then return end
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")

-- Prevent redundant plugin reloading during playtests
if RunService:IsRunning() then return end

local PLUGIN_NAME = "Custom Function Comments"
local AUTOCOMPLETE_NAME = "CustomFunctionComments"
local AUTOCOMPLETE_PRIORITY = 1000

if script:IsDescendantOf(game:GetService("PluginDebugService")) then
	AUTOCOMPLETE_NAME ..= "_Debug"
end

type Request = {
	position: {
		line: number,
		character: number,
	},
	textDocument: {
		document: ScriptDocument?,
		script: LuaSourceContainer?,
	},
}

type ResponseItem = {
	codeSample: string,
	learnMoreLink: string,
	label: string,
	kind: Enum.CompletionItemKind?,
	tags: {Enum.CompletionItemTag}?,
	detail: string?,
	documentation: {
		value: string,
	}?,
	preselect: boolean?,
	textEdit: {
		newText: string,
		replace: { 
			start: { line: number?, character: number? }, 
			["end"]: { line: number?, character: number? },
		},
	}?,
}

type Response = {
	items: { ResponseItem },
}

-- Parse markdown syntax
local function parseMarkdown(text: string)
	-- Helper function to handle escaped markdown
	local function escapeMarkdown(str)
		-- Replace escaped markdown symbols with placeholders
		str = str:gsub("\\%*%*", "##ESCBOLD##")
		str = str:gsub("\\%*", "##ESCITALIC##")
		str = str:gsub("\\%^", "##ESCSUP##")
		str = str:gsub("\\`", "##ESCCODE##")
		return str
	end

	-- Helper function to restore escaped markdown
	local function restoreEscaped(str)
		str = str:gsub("##ESCBOLD##", "**")
		str = str:gsub("##ESCITALIC##", "*")
		str = str:gsub("##ESCSUP##", "^")
		str = str:gsub("##ESCCODE##", "`")
		return str
	end

	-- Escape backslash sequences first
	text = escapeMarkdown(text)

	-- Process bold text: ** text **
	text = text:gsub("%*%*([^%*]+)%*%*", "<strong>%1</strong>")

	-- Process italic text: * text *
	text = text:gsub("%*([^%*]+)%*", "<em>%1</em>")

	-- Process superscript: ^ text ^
	text = text:gsub("%^([^%^]+)%^", "<sup>%1</sup>")

	-- Process code: ` text `
	text = text:gsub("`([^`]+)`", "<code>%1</code>")

	-- Restore escaped sequences
	text = restoreEscaped(text)

	return text
end

-- Process line breaks based on whitespace
local function processLineBreaks(text: string)
	-- Look for consecutive line breaks and preserve them (double line breaks)
	text = text:gsub("<br>%s*<br>", "##KEEPBREAK##")

	-- Remove line breaks with preceding whitespace and any trailing whitespace
	text = text:gsub("%s+<br>%s*", " ")

	-- Restore preserved line breaks
	text = text:gsub("##KEEPBREAK##", "<br><br>")

	return text
end

local function AutocompleteCallback(req: Request, res: Response)
	for _, item in res.items do
		-- Prevent processing items that aren't functions, are official api functions, or don't have a comment to parse
		if item.kind ~= Enum.CompletionItemKind.Function then continue end
		if item.learnMoreLink ~= "" then continue end
		if item.documentation.value == "" then continue end

		-- Remove surrounding <p>..</p> tags for processing
		local comment = item.documentation.value:sub(4, -5)

		-- Check for <dep> deprecated tag
		if comment:match("<dep>") then
			table.insert(item.tags, Enum.CompletionItemTag.Deprecated)
			comment = comment:gsub("<dep>%s*<br>%s*", "") -- Trims trailing whitespace AND line break
			comment = comment:gsub("<dep>%s*", "") -- Trims trailing whitespace without line break
		end

		-- Check for <doc> tag and extract link
		local docLink = comment:match("<doc>(.-)</doc>")
		if docLink then
			item.learnMoreLink = docLink:match("^%s*(.-)%s*$") -- Trim preceding whitespace
			comment = comment:gsub("<doc>.-</doc>%s*<br>%s*", "")
			comment = comment:gsub("<doc>.-</doc>%s*", "")
		end

		-- Markdown code sample detection
		local codeSample = comment:match("```(.*)")

		-- Process Code Sample if found
		if codeSample then
			-- Process code sample: replace <br> followed by tabs with newlines
			codeSample = codeSample:gsub("<br>%s*\t+", "\n")
			-- Remove any remaining <br> tags
			codeSample = codeSample:gsub("<br>", "\n")

			--Trim closing tag IF present at end of code sample
			codeSample = codeSample:gsub("%s*```%s*$", "")

			item.codeSample = codeSample:match("^%s*(.-)%s*$") -- Trim preceding whitespace

			-- Remove code sample and cs tag from the comment
			comment = comment:gsub("<br>%s*```.*", "")
			comment = comment:gsub("```.*", "")
		end

		-- Process line breaks based on whitespace
		comment = processLineBreaks(comment)

		-- Finally parse markdown and readd surrounding <p>..</p> tags
		-- Side Note: These aren't integral to the comment (?) but are nonetheless present in every comment
		item.documentation.value = "<p>" .. parseMarkdown(comment) .. "</p>"
	end
	return res
end

local function RegisterCallback()
	ScriptEditorService:RegisterAutocompleteCallback(AUTOCOMPLETE_NAME, AUTOCOMPLETE_PRIORITY, AutocompleteCallback)
end

if not pcall(RegisterCallback) then
	LogService:Warn(`Script modification permission required to register {PLUGIN_NAME} autocompletion callback; retrying in 10 seconds`)
	task.wait(10)

	if pcall(RegisterCallback) then
		LogService:Info(`Successfully registered {PLUGIN_NAME} autocompletion callback`)
	else
		LogService:Warn(`Failed to register {PLUGIN_NAME} autocompletion callback; script modification permission never granted`)
		LogService:Info(`Manually Grant Permission/Restart Plugin:`)
		LogService:Info(`1. Plugins (Topbar) → Manage Plugins`)
		LogService:Info(`2. Manage Plugins → {PLUGIN_NAME}`)
		LogService:Info(`3. {PLUGIN_NAME} → Script Injection Denied (Right Edit Icon)`)
		LogService:Info(`4. Script Injection → True`)
		LogService:Info(`5. Disable/Enable Plugin to Retry (No Print If Successful)`)
		return
	end
end

plugin.Unloading:Connect(function()
	ScriptEditorService:DeregisterAutocompleteCallback(AUTOCOMPLETE_NAME)
end)