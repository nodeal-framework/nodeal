--!native
--!optimize 2

local Type = {}

Type.completion = {
	kind = Enum.CompletionItemKind.Class,
	detail = "Split<S: string, D: string>",
	documentation = "Splits string S by delimiter D, returning a union of the resulting string literal types.",
	args = { "S", "D" }
}

function Type.resolve(args, parser)
	local str = args[1] and args[1].value or ""
	local delim = args[2] and args[2].value or ""

	local parts = {}
	if delim == "" then
		for idx = 1, #str do
			table.insert(parts, '"' .. str:sub(idx, idx) .. '"')
		end
	else
		local start = 1
		while true do
			local s, e = str:find(delim, start, true)
			if not s then
				table.insert(parts, '"' .. str:sub(start) .. '"')
				break
			end
			table.insert(parts, '"' .. str:sub(start, s - 1) .. '"')
			start = e + 1
		end
	end

	local typeName = #parts > 0 and table.concat(parts, " | ") or "string"
	return {}, typeName
end

return Type