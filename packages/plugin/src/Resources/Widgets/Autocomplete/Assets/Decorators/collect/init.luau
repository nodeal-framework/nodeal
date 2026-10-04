local collect = {}

collect.completion = {
	kind = Enum.CompletionItemKind.Event,
	detail = `@{script.Name}`,
	documentation = "Instructs the decorator to collect all its decorated function targets into the defining module's payload (.collected).",
	args = {},

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

return collect
