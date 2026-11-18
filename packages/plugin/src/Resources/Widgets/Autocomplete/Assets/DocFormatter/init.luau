--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Documentation Formatter //--
-- Generic rendering engine for documentation tags.
--
-- Tag modules own everything specific to them: glyph, ordering, grouping and
-- line rendering. This module only provides collection, inline formatting and
-- the assembly of the final value.
--
-- Roblox does not parse markdown for us, so a tiny inline syntax is converted
-- here. The panel understands the same small HTML subset Studio uses for its
-- own doc comments: `<p>`, `<br>`, `<strong>`, `<em>`, `<code>` and `<sup>`.
--
-- Spec contract (defined by each decorator module):
--   order: number?            global ordering, lowest renders first
--   group: any?               consecutive entries from different groups get a group separator
--   identity(values): any?    optional dedupe key; the latest value wins
--   render(values): string?   final line, or nil to skip the entry

local DocFormatter = {}

--// Configuration //--

DocFormatter.USE_CODE_TAG = true

-- Studio wraps its own documentation values in `<p>...</p>`. Mirroring that
-- shape keeps spacing consistent with native entries.
DocFormatter.WRAP_IN_PARAGRAPH = true

-- Set to `false` to leave `<` and `>` untouched inside descriptions.
DocFormatter.ESCAPE_HTML = false

-- `<br>` between two lines.
DocFormatter.LINE_SEPARATOR = "<br>"

-- Gap between two groups. A thin superscript space gives a line shorter than a
-- full blank line, while still being a real line break (supported by the docs
-- panel). Use "<br>" for no gap or "<br><br>" for a full blank line.
DocFormatter.GROUP_SEPARATOR = "<br><br>"

-- Gap between the free-form description and the first group.
DocFormatter.PROSE_SEPARATOR = "<br><br>"

--// Helpers //--

local ESCAPED_BOLD = string.char(1)
local ESCAPED_ITALIC = string.char(2)
local ESCAPED_SUP = string.char(3)
local ESCAPED_CODE = string.char(4)

local function trim(text: string): string
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function protectEscapes(text: string): string
	text = text:gsub("\\%*%*", ESCAPED_BOLD)
	text = text:gsub("\\%*", ESCAPED_ITALIC)
	text = text:gsub("\\%^", ESCAPED_SUP)
	text = text:gsub("\\`", ESCAPED_CODE)
	return text
end

local function restoreEscapes(text: string): string
	text = text:gsub(ESCAPED_BOLD, "**")
	text = text:gsub(ESCAPED_ITALIC, "*")
	text = text:gsub(ESCAPED_SUP, "^")
	text = text:gsub(ESCAPED_CODE, "`")
	return text
end

local function escapeHTML(text: string): string
	if not DocFormatter.ESCAPE_HTML then
		return text
	end

	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end

--// Formatting primitives //--

function DocFormatter.formatInline(text: string?, singleLine: boolean?): string
	if type(text) ~= "string" or text == "" then
		return ""
	end

	if singleLine then
		text = text:gsub("%s*\n%s*", " ")
	end

	text = protectEscapes(text)
	text = escapeHTML(text)

	text = text:gsub("%*%*([^%*\n]+)%*%*", "<strong>%1</strong>")
	text = text:gsub("%*([^%*\n]+)%*", "<em>%1</em>")
	text = text:gsub("%^([^%^\n]+)%^", "<sup>%1</sup>")

	if DocFormatter.USE_CODE_TAG then
		text = text:gsub("`([^`\n]+)`", "<code>%1</code>")
	end

	text = restoreEscapes(text)

	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	text = text:gsub("[ \t]+\n", "\n"):gsub("\n[ \t]+", "\n")
	text = trim(text)
	text = text:gsub("\n", DocFormatter.LINE_SEPARATOR)

	return text
end

function DocFormatter.formatStrong(text: string): string
	return "<strong>" .. escapeHTML(text) .. "</strong>"
end

function DocFormatter.joinTokens(tokens: { any }, startIndex: number?): string
	-- The parser emits a lone `true` when a decorator has no arguments at all.
	if #tokens == 1 and tokens[1] == true then
		return ""
	end

	local parts = {}
	local first = startIndex or 1

	for index = first, #tokens do
		local value = tokens[index]
		local kind = type(value)
		if kind == "string" then
			table.insert(parts, value)
		elseif kind == "number" or kind == "boolean" then
			table.insert(parts, tostring(value))
		end
	end

	return trim(table.concat(parts, " "))
end

--// Collection //--

function DocFormatter.getEntries(item: any): { any }?
	if type(item) ~= "table" then
		return nil
	end

	local entries = item.__docEntries
	if not entries then
		entries = {}
		item.__docEntries = entries
	end

	return entries
end

function DocFormatter.add(item: any, spec: any, ...: any): ()
	if type(spec) ~= "table" or type(spec.render) ~= "function" then
		return
	end

	local entries = DocFormatter.getEntries(item)
	if not entries then
		return
	end

	local values = table.pack(...)
	local key = nil
	if type(spec.identity) == "function" then
		key = spec.identity(values)
	end

	if key ~= nil then
		for _, entry in entries do
			if entry.spec == spec and entry.key == key then
				entry.values = values
				return
			end
		end
	end

	table.insert(entries, {
		spec = spec,
		values = values,
		key = key,
		index = #entries + 1,
	})
end

--// Rendering //--

local function renderEntries(entries: { any }): string
	local ordered = table.clone(entries)

	table.sort(ordered, function(a: any, b: any): boolean
		local orderA = a.spec.order or math.huge
		local orderB = b.spec.order or math.huge
		if orderA == orderB then
			return a.index < b.index
		end
		return orderA < orderB
	end)

	local chunks = {}
	local current = nil

	for _, entry in ordered do
		local line = entry.spec.render(entry.values)
		if type(line) ~= "string" or line == "" then
			continue
		end

		local group = entry.spec.group or entry.spec

		if not current or current.group ~= group then
			current = {
				group = group,
				lines = {},
			}
			table.insert(chunks, current)
		end

		table.insert(current.lines, line)
	end

	local rendered = {}
	for _, chunk in chunks do
		table.insert(rendered, table.concat(chunk.lines, DocFormatter.LINE_SEPARATOR))
	end

	return table.concat(rendered, DocFormatter.GROUP_SEPARATOR)
end

function DocFormatter.render(documentation: any, entries: { any }?): string
	if type(documentation) == "table" then
		documentation = documentation.value
	end

	local prose = type(documentation) == "string" and trim(documentation) or ""
	local body = renderEntries(entries or {})

	if body == "" then
		-- No tag produced a line: keep the original documentation untouched
		-- instead of introducing an empty paragraph.
		return type(documentation) == "string" and documentation or ""
	end

	local formattedProse = DocFormatter.formatInline(prose)
	if formattedProse ~= "" then
		body = formattedProse .. DocFormatter.PROSE_SEPARATOR .. body
	end

	if DocFormatter.WRAP_IN_PARAGRAPH then
		body = "<p>" .. body .. "</p>"
	end

	return body
end

return DocFormatter
