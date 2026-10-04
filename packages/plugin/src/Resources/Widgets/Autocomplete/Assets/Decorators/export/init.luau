local export = {}

export.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name} <...export: string>`,
	documentation = "Activates a dynamic metadata extractor (e.g., type, code).",
	args = {
		variadic = {
			"documentation", "name", 
			"arguments", "arguments:simple", "arguments:advanced", 
			"returns", "returns:simple", "returns:advanced", 
			"prototype", "usages"
		}
	},

	context = function(source: string, line: number)
		local lines = string.split(source, "\n")

		for i = line + 1, #lines do
			local l = lines[i]
			l = string.match(l, "^%s*(.-)%s*$")

			if l == "" or string.match(l, "^%]") or string.match(l, "^%-%-") then
				continue
			end

			if string.match(l, "game:RegisterDecorator") then
				return true
			end

			return false
		end

		return false
	end
}

return export