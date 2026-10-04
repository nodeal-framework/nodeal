--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local HttpService = game:GetService("HttpService")

local PackagesHandler = {}

-- ══════════════════════════════════════════════════════════════
--  CONSTANTS
-- ══════════════════════════════════════════════════════════════

local _BASE_URL = "https://api.nodeal.dev"

-- ══════════════════════════════════════════════════════════════
--  PRIVATE UTILS
-- ══════════════════════════════════════════════════════════════

local function _request(method: string, path: string, payload: any?, token: string?): (boolean, any)
	local headers = { ["Content-Type"] = "application/json" }
	if token then headers["Authorization"] = "Bearer " .. token end

	local options = {
		Url = _BASE_URL .. path,
		Method = method,
		Headers = headers,
	}

	if payload then
		if type(payload) == "table" then
			options.Body = HttpService:JSONEncode(payload)
		elseif type(payload) == "string" then
			options.Body = payload
			if method == "PUT" and string.match(path, "/documentation/") then
				headers["Content-Type"] = "text/plain"
			elseif method == "POST" and string.match(path, "/versions") then
				headers["Content-Type"] = "application/octet-stream"
			elseif method == "PUT" and string.match(path, "/icon") then
				headers["Content-Type"] = "application/octet-stream"
			end
		end
	end

	local ok, res = pcall(HttpService.RequestAsync, HttpService, options)
	if not ok then return false, { error = tostring(res) } end

	local body = pcall(function() return HttpService:JSONDecode(res.Body) end)
		and HttpService:JSONDecode(res.Body)
		or  { error = res.Body }

	return res.StatusCode >= 200 and res.StatusCode < 300, body
end

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API: PACKAGES METADATA
-- ══════════════════════════════════════════════════════════════

function PackagesHandler.GetPackages(query: string?, page: number?, limit: number?, sortBy: string?, sortOrder: string?): (boolean, any)
	local path = "/api/v1/packages"
	local params = {}

	if query and query ~= "" then table.insert(params, "q=" .. HttpService:UrlEncode(query)) end
	if page then table.insert(params, "page=" .. tostring(page)) end
	if limit then table.insert(params, "limit=" .. tostring(limit)) end
	if sortBy and sortBy ~= "" then table.insert(params, "sortBy=" .. HttpService:UrlEncode(sortBy)) end
	if sortOrder and sortOrder ~= "" then table.insert(params, "sortOrder=" .. HttpService:UrlEncode(sortOrder)) end

	if #params > 0 then
		path ..= "?" .. table.concat(params, "&")
	end

	return _request("GET", path)
end

function PackagesHandler.GetSortOptions(): (boolean, any)
	return _request("GET", "/api/v1/packages/sort-options")
end

function PackagesHandler.GetPackage(packageId: string): (boolean, any)
	assert(packageId, "[Nodeal] packageId is required")
	return _request("GET", "/api/v1/packages/" .. packageId)
end

function PackagesHandler.CreatePackage(token: string, packageId: string, name: string, description: string, tags: {string}?, links: {any}?, iconId: string?): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and name and description, "[Nodeal] Missing required fields")

	return _request("POST", "/api/v1/packages", {
		id = packageId,
		name = name,
		description = description,
		tags = tags,
		links = links,
		iconId = iconId
	}, token)
end

function PackagesHandler.UpdatePackage(token: string, packageId: string, data: {name: string?, description: string?, iconId: string?}): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId, "[Nodeal] packageId is required")

	return _request("PATCH", "/api/v1/packages/" .. packageId, data, token)
end

function PackagesHandler.DeletePackage(token: string, packageId: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId, "[Nodeal] packageId is required")

	return _request("DELETE", "/api/v1/packages/" .. packageId, nil, token)
end

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API: VERSIONS & UPLOADS
-- ══════════════════════════════════════════════════════════════

function PackagesHandler.GetVersions(packageId: string): (boolean, any)
	assert(packageId, "[Nodeal] packageId is required")
	return _request("GET", "/api/v1/packages/" .. packageId .. "/versions")
end

function PackagesHandler.UploadVersion(token: string, packageId: string, version: string, rbxmContent: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and version and rbxmContent, "[Nodeal] Missing fields")

	return _request("POST", "/api/v1/packages/" .. packageId .. "/versions?version=" .. HttpService:UrlEncode(version), rbxmContent, token)
end

function PackagesHandler.UploadIconFile(token: string, packageId: string, imageContent: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and imageContent, "[Nodeal] Missing fields")

	return _request("PUT", "/api/v1/packages/" .. packageId .. "/icon", imageContent, token)
end

function PackagesHandler.DownloadVersion(packageId: string, version: string): (boolean, string | any)
	assert(packageId and version, "[Nodeal] packageId and version are required")
	local ok, data = _request("GET", "/api/v1/packages/" .. packageId .. "/versions/" .. version .. "/download")

	if ok then
		return true, type(data) == "table" and data.error or data
	end

	return false, data
end

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API: CONTENT (CHANGELOG & DOCS)
-- ══════════════════════════════════════════════════════════════

function PackagesHandler.UploadChangelog(token: string, packageId: string, changelogEntries: {any}): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and changelogEntries, "[Nodeal] Missing fields")

	return _request("PUT", "/api/v1/packages/" .. packageId .. "/changelog", changelogEntries, token)
end

function PackagesHandler.UploadDocumentation(token: string, packageId: string, docType: string, slugArray: {string}, markdownContent: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and docType and slugArray and markdownContent, "[Nodeal] Missing fields")

	local path = "/api/v1/packages/" .. packageId .. "/documentation/" .. docType .. "/" .. table.concat(slugArray, "/")
	return _request("PUT", path, markdownContent, token)
end

function PackagesHandler.DeleteDocumentation(token: string, packageId: string, docType: string, slugArray: {string}): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and docType and slugArray, "[Nodeal] Missing fields")

	local path = "/api/v1/packages/" .. packageId .. "/documentation/" .. docType .. "/" .. table.concat(slugArray, "/")
	return _request("DELETE", path, nil, token)
end

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API: SOCIAL
-- ══════════════════════════════════════════════════════════════

function PackagesHandler.ToggleLike(token: string, packageId: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId, "[Nodeal] packageId is required")

	return _request("POST", "/api/v1/packages/" .. packageId .. "/interactions", { type = "LIKE" }, token)
end

function PackagesHandler.AddComment(token: string, packageId: string, content: string): (boolean, any)
	assert(token, "[Nodeal] Unauthorized: You must be logged in.")
	assert(packageId and content, "[Nodeal] Missing fields")

	return _request("POST", "/api/v1/packages/" .. packageId .. "/comments", { content = content }, token)
end

return PackagesHandler