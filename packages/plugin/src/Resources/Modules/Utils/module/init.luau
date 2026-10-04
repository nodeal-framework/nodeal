--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local utils, Module = nil, {}

local function assert(condition: any?, message: string?): ()
	if condition then return end

	error(message or "Condition Failed", 3)
end

local function _get_decorator_args(list: {any}, name: string): {any}
	for _, data in ipairs(list) do
		if data[1] == name then
			return data[2] or {}
		end
	end
	return nil
end

local HttpService = game:GetService("HttpService")

function Module.get_header(module: ModuleScript?): { [any]: any }
	assert(module and module:IsA("ModuleScript"), "Argument 1 missing or not a 'ModuleScript'")

	local header_success, header_content = pcall(function()
		return HttpService:JSONDecode(module:GetAttribute("ContentHeader"))
	end)

	return header_success and header_content or {}
end

function Module.get_payload(module: ModuleScript?): { [any]: any }
	assert(module and module:IsA("ModuleScript"), "Argument 1 missing or not a 'ModuleScript'")

	local payload_success, payload_content = pcall(function()
		return HttpService:JSONDecode(module:GetAttribute("ContentPayload"))
	end)

	return payload_success and payload_content or {}
end

function Module.get_metadata(module: ModuleScript?): { ["module"]: { any }, ["content"]: { any } }
	return {
		header = Module.get_header(module),
		payload = Module.get_payload(module)
	}
end

function Module.get_context(instance: Instance?, ignore_metadata: boolean?): { "client" | "server" }
	if not instance then
		return {}
	end

	local inherited_contexts = {}

	if instance:HasTag(utils.manifest.TagRoot) then
		local attributes = instance:GetAttributes()

		if attributes.ContextClient then
			table.insert(inherited_contexts, "client")
		end

		if attributes.ContextServer then
			table.insert(inherited_contexts, "server")
		end
	else
		inherited_contexts = Module.get_context(instance.Parent, ignore_metadata)
	end

	if instance:IsA("ModuleScript") and not ignore_metadata then
		local header = Module.get_header(instance) or {}
		local filtered_contexts = {}

		local client = _get_decorator_args(header, "client")
		local server = _get_decorator_args(header, "server")

		local has_explicit_true = (client and client[1] == true) or (server and server[1] == true)

		if has_explicit_true then
			if (client and client[1] == true) and table.find(inherited_contexts, "client") then
				table.insert(filtered_contexts, "client")
			end

			if (server and server[1] == true) and table.find(inherited_contexts, "server") then
				table.insert(filtered_contexts, "server")
			end
		else
			if (not client or client[1] ~= false) and table.find(inherited_contexts, "client") then
				table.insert(filtered_contexts, "client")
			end

			if (not server or server[1] ~= false) and table.find(inherited_contexts, "server") then
				table.insert(filtered_contexts, "server")
			end
		end

		return filtered_contexts
	end

	return inherited_contexts
end

function Module.has_universal_access(origin_context: {string}, completion: any): boolean
	if not completion or not completion.crossContexts then return false end
	for _, ctx in completion.crossContexts do
		if ctx == "*" or table.find(origin_context, ctx) then
			return true
		end
	end
	return false
end

function Module.is_module_accessible(origin_context: {string}, target_context: {string}, types: any?): boolean
	local has_overlap = false
	for _, o_ctx in origin_context do
		if table.find(target_context, o_ctx) then
			has_overlap = true
			break
		end
	end

	if has_overlap then return true end
	if not types then return false end

	local returnTable = types or {}
	if type(returnTable.completion) == "table" and Module.has_universal_access(origin_context, returnTable.completion) then
		return true
	end

	if returnTable.next then
		for _, item in returnTable.next do
			if type(item) == "table" and Module.has_universal_access(origin_context, item.completion) then
				return true
			end
		end
	else
		for key, item in returnTable do
			if type(key) == "string" and type(item) == "table" and Module.has_universal_access(origin_context, item.completion) then
				return true
			end
		end
	end

	return false
end

function Module.is_sandboxed(instance: Instance): boolean
	if not instance or not instance:IsA("ModuleScript") then
		return true
	end

	-- local hasReturn = self.source:match("return%s+__%s*%(.-%)") ~= nil
	return string.find(instance.Source, "return%s+setfenv") ~= nil
end

function Module.Init(_utils: { [string]: { [string]: (any) -> (any) } }): ()
	utils = _utils
end

return Module