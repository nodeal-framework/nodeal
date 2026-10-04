return function(parser)
	local source = parser.source
	local returnedName = source:match("return%s+__%(([%w_]+)%)")
	local returnLine = nil
	local returnLineIndex = nil
	for idx = #parser.lines, 1, -1 do
		local line = parser.lines[idx]
		if line:match("^%s*return%s+") then
			returnLine = line
			returnLineIndex = idx
			break
		end
	end

	if not returnedName and parser.allowNonNodeal and returnLine then
		returnedName = returnLine:match("return%s+%(?%s*([%w_]+)%s*::")
		if not returnedName then
			returnedName = returnLine:match("return%s+%(?%s*([%w_]+)%s*%)?%s*::")
		end
		if not returnedName then
			returnedName = returnLine:match("return%s+([%w_]+)")
		end
	end

	if not returnedName or not returnLineIndex then return end

	local docText, meta = parser:GetDocBeforeLine(returnLineIndex)

	parser.tables[returnedName] = parser.tables[returnedName] or {}
	parser.tables[returnedName].__return = parser:CreateCompletionItem({
		name = "__return",
		type = "returned",
		documentation = docText,
		decorators = meta
	})
end