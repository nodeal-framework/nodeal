--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local functions = {}

local _parser: { [string]: { [string]: (any) -> (any) } }

local function _normalize_type(t: string): string
	t = string.gsub(t, "%s+", "")
	if t == "" then return "any" end

	while string.sub(t, 1, 1) == "(" and string.sub(t, -1) == ")" do
		local depth = 0
		local can_strip = true

		for i = 1, #t - 1 do 
			local b = string.byte(t, i)
			local prev = i > 1 and string.byte(t, i - 1) or nil

			if b == 40 or b == 60 or b == 123 or b == 91 then depth += 1
			elseif b == 41 or b == 125 or b == 93 then depth -= 1
			elseif b == 62 and prev ~= 45 then depth -= 1
			end

			if depth == 0 then
				can_strip = false
				break
			end
		end

		if can_strip then
			t = string.sub(t, 2, -2)
		else
			break
		end
	end

	return t
end

local function _parse_balanced(str: string): { string }
	local list = {}
	local depth = 0
	local start_idx = 1
	local len = #str

	for i = 1, len do
		local b = string.byte(str, i)
		local prev = i > 1 and string.byte(str, i - 1) or nil

		if b == 40 or b == 60 or b == 123 or b == 91 then depth += 1
		elseif b == 41 or b == 125 or b == 93 then depth -= 1
		elseif b == 62 and prev ~= 45 then depth -= 1
		elseif b == 44 and depth == 0 then
			local raw = string.sub(str, start_idx, i - 1)
			table.insert(list, _normalize_type(raw))
			start_idx = i + 1
		end
	end

	if start_idx <= len then
		local raw = string.sub(str, start_idx)
		table.insert(list, _normalize_type(raw))
	end

	return list
end

function functions.extract_prototype(code: string): string
	local args_open = string.find(code, "%(")
	if not args_open then return code end

	local args_close = args_open
	local depth = 0
	for i = args_open, #code do
		local b = string.byte(code, i)
		if b == 40 then depth += 1 elseif b == 41 then depth -= 1 end
		if depth == 0 then args_close = i; break end
	end

	local signature = string.sub(code, 1, args_close)
	local after = string.sub(code, args_close + 1)

	local colon_idx = string.find(after, ":")
	if colon_idx then
		local before_colon = string.sub(after, 1, colon_idx - 1)
		if not string.find(before_colon, "%S") then
			local end_of_sig = string.find(after, "[\r\n]", colon_idx) or #after
			signature ..= " " .. string.sub(after, colon_idx, end_of_sig)
		end
	end

	signature = string.gsub(signature, "%s+", " ")
	return string.match(signature, "^%s*(.-)%s*$") or ""
end

function functions.extract_infos(prototype: string): { [string]: any }
	local args_open = string.find(prototype, "%(")
	if not args_open then return nil end

	local args_close = args_open
	local depth = 0
	for i = args_open, #prototype do
		local b = string.byte(prototype, i)
		if b == 40 then depth += 1 elseif b == 41 then depth -= 1 end
		if depth == 0 then args_close = i; break end
	end

	local header = string.sub(prototype, 1, args_open - 1)
	local name = string.match(header, "^%s*([%w_]+)")
	local generics = {}

	local gen_content = string.match(header, "<(.*)>")

	if gen_content then 
		generics = _parse_balanced(gen_content) 
	end

	local raw_args_content = string.sub(prototype, args_open + 1, args_close - 1)

	local function split_raw(s)
		local l = {}
		local d = 0
		local st = 1
		for i=1, #s do
			local b = string.byte(s, i)
			local prev = i > 1 and string.byte(s, i - 1) or nil

			if b==40 or b==60 or b==123 or b==91 then d+=1 
			elseif b==41 or b==125 or b==93 then d-=1
			elseif b==62 and prev~=45 then d-=1
			end

			if b==44 and d==0 then table.insert(l, string.sub(s,st,i-1)); st=i+1 end
		end
		if st<=#s then table.insert(l, string.sub(s,st)) end
		return l
	end

	local raw_args = split_raw(raw_args_content)
	local args_parsed = {}

	for _, arg in ipairs(raw_args) do
		arg = string.match(arg, "^%s*(.-)%s*$") or ""

		if arg == "..." then
			table.insert(args_parsed, {name="...", type="any", optional=true})
		elseif arg ~= "" then
			local n, t = string.match(arg, "^([%w_%.%?]+)%s*:%s*(.+)$")
			if n then
				local is_opt = (string.sub(n, -1) == "?") or (string.sub(t, -1) == "?")
				local clean_type = _normalize_type(string.gsub(t, "%?$", ""))

				table.insert(args_parsed, {
					name = string.gsub(n, "%?$", ""),
					type = clean_type,
					optional = is_opt
				})
			else
				table.insert(args_parsed, {name=arg, type="any", optional=false})
			end
		end
	end

	local after_args = string.sub(prototype, args_close + 1)
	local ret_str = string.match(after_args, ":%s*(.*)$")
	local returns = {}

	if ret_str then
		ret_str = string.match(ret_str, "^%s*(.-)%s*$")
		if string.sub(ret_str, 1, 1) == "(" and string.sub(ret_str, -1) == ")" then
			local inside = string.sub(ret_str, 2, -2)
			local parsed = _parse_balanced(inside)
			if #parsed > 1 then
				returns = parsed
			else
				returns = {_normalize_type(ret_str)}
			end
		else
			returns = {_normalize_type(ret_str)}
		end
	else
		returns = {"void"}
	end

	return {
		name = name,
		generics = generics,
		arguments = args_parsed,
		returns = returns
	}
end

function functions.get_infos(item: any): { [string]: any }
	item.cache = item.cache or {}
	if item.cache.signature then return item.cache.signature end

	local infos = functions.extract_infos(item.prototype)

	if table.find(item.methodes, ":") then
		table.insert(infos.arguments, 1, {
			name = "self",
			type = "any",
			optional = false
		})
	end

	item.cache.signature = infos
	return infos
end

function functions.Init(p)
	_parser = p
end

return functions