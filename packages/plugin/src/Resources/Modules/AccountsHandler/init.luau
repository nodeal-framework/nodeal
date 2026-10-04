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

local AccountsHandler = {}

-- ══════════════════════════════════════════════════════════════
--  TYPES
-- ══════════════════════════════════════════════════════════════

export type Account = {
	token: string,
	userId: string,
	username: string,
	addedAt: number,
	lastUsed: number,
}

export type LinkSession = {
	code: string,
	url: string,
	expiresAt: string,
	secret: string,
}

export type PollStatus = "PENDING" | "AUTHORIZED" | "EXPIRED" | "CONSUMED" | "ERROR"

-- ══════════════════════════════════════════════════════════════
--  CONSTANTS
-- ══════════════════════════════════════════════════════════════

local _BASE_URL = "https://api.nodeal.dev"
local _STORE_KEY = "Nodeal:Accounts:List"
local _STORE_ACTIVE_KEY = "Nodeal:Accounts:Active"
local _MAX_ACCOUNTS = 10
local _POLL_INTERVAL = 3
local _POLL_TIMEOUT = 600

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════

local _plugin: Plugin
local _activeToken: string?  = nil
local _activeAccount: Account? = nil
local _onStateListeners: { (string?) -> () } = {}

-- ══════════════════════════════════════════════════════════════
--  PRIVATE UTILS
-- ══════════════════════════════════════════════════════════════

local function _generateSecret(): string
	local characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local secret = ""
	for i = 1, 32 do
		local rand = math.random(1, #characters)
		secret ..= string.sub(characters, rand, rand)
	end
	return secret
end

local function _get(path: string, token: string?): (boolean, any)
	local headers = { ["Content-Type"] = "application/json" }
	if token then headers["Authorization"] = "Bearer " .. token end
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = _BASE_URL .. path,
		Method = "GET",
		Headers = headers,
	})
	if not ok then return false, { error = tostring(res) } end
	local body = pcall(function() return HttpService:JSONDecode(res.Body) end)
		and HttpService:JSONDecode(res.Body)
		or  { error = res.Body }
	return res.StatusCode >= 200 and res.StatusCode < 300, body
end

local function _post(path: string, payload: any, token: string?): (boolean, any)
	local headers = { ["Content-Type"] = "application/json" }
	if token then headers["Authorization"] = "Bearer " .. token end
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = _BASE_URL .. path,
		Method = "POST",
		Headers = headers,
		Body = HttpService:JSONEncode(payload),
	})
	if not ok then return false, { error = tostring(res) } end
	local body = pcall(function() return HttpService:JSONDecode(res.Body) end)
		and HttpService:JSONDecode(res.Body)
		or  { error = res.Body }
	return res.StatusCode >= 200 and res.StatusCode < 300, body
end

local function _delete(path: string, payload: any, token: string): (boolean, any)
	local headers = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. token,
	}
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url = _BASE_URL .. path,
		Method = "DELETE",
		Headers = headers,
		Body = HttpService:JSONEncode(payload),
	})
	if not ok then return false, { error = tostring(res) } end
	local body = pcall(function() return HttpService:JSONDecode(res.Body) end)
		and HttpService:JSONDecode(res.Body)
		or  { error = res.Body }
	return res.StatusCode >= 200 and res.StatusCode < 300, body
end

local function _loadAccounts(): { Account }
	local raw = _plugin:GetSetting(_STORE_KEY)
	if type(raw) ~= "table" then return {} end
	return raw :: { Account }
end

local function _saveAccounts(list: { Account })
	_plugin:SetSetting(_STORE_KEY, list)
end

local function _persistActiveToken(token: string?)
	_plugin:SetSetting(_STORE_ACTIVE_KEY, token)
end

local function _loadActiveToken(): string?
	local v = _plugin:GetSetting(_STORE_ACTIVE_KEY)
	return if type(v) == "string" and v ~= "" then v else nil
end

local function _upsertAccount(account: Account)
	local list = _loadAccounts()
	for _, acc in list do
		if acc.token == account.token then
			acc.username = account.username
			acc.userId = account.userId
			acc.lastUsed = account.lastUsed
			_saveAccounts(list)
			return
		end
	end
	if #list >= _MAX_ACCOUNTS then
		table.sort(list, function(a, b) return a.lastUsed < b.lastUsed end)
		table.remove(list, 1)
	end
	table.insert(list, account)
	_saveAccounts(list)
end

local function _notifyState()
	for _, fn in _onStateListeners do
		local ok, err = pcall(fn, _activeToken, _activeAccount)
		if not ok then warn("[Nodeal]", err) end
	end
end

local function _buildAvatarUrl(userId: string|number, params: { [string]: any }?): string
	local p = params or {}
	local thumbType = p.type or "AvatarHeadShot"
	local w = p.w or 420
	local h = p.h or 420

	return string.format(
		"rbxthumb://type=%s&id=%s&w=%d&h=%d&filters=circular",
		thumbType, tostring(userId), w, h
	)
end

local function _validateAccounts()
	local list = _loadAccounts()
	if #list == 0 then return end

	local tokens = {}
	for _, acc in list do
		table.insert(tokens, acc.token)
	end

	local ok, body = _post("/account/tokens/verify", { tokens = tokens })
	if not ok then return end

	local invalidTokens = body.invalidTokens or {}
	if #invalidTokens == 0 then return end

	-- Build new list excluding invalid tokens
	local newList = {}
	local activeTokenWasInvalid = false

	for _, acc in list do
		local isValid = true
		for _, invToken in invalidTokens do
			if acc.token == invToken then
				isValid = false
				break
			end
		end

		if isValid then
			table.insert(newList, acc)
		else
			if acc.token == _activeToken then
				activeTokenWasInvalid = true
			end
		end
	end

	_saveAccounts(newList)

	if activeTokenWasInvalid then
		if #newList > 0 then
			AccountsHandler.SetActiveToken(newList[1].token)
		else
			_activeToken = nil
			_activeAccount = nil
			_persistActiveToken(nil)
			_notifyState()
		end
	end
end

-- ══════════════════════════════════════════════════════════════
--  PUBLIC API
-- ══════════════════════════════════════════════════════════════

function AccountsHandler.Init(container: any)
	assert(container.plugin ~= nil, "[Nodeal] Init() requires the plugin container object.")

	_plugin = container.plugin
	_activeToken = _loadActiveToken()

	if _activeToken then
		for _, acc in _loadAccounts() do
			if acc.token == _activeToken then
				_activeAccount = acc
				break
			end
		end
	end

	math.randomseed(os.time())

	-- Verify saved tokens asynchronously
	task.spawn(_validateAccounts)
end

function AccountsHandler.InitLink(): (boolean, any)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	local secret = _generateSecret()
	local ok, body = _post("/auth/link/init", {
		clientSecret = secret
	})
	if ok then
		body.secret = secret
	end
	return ok, body
end

function AccountsHandler.PollLinkStatus(
	session     : LinkSession,
	onAuthorized: (string, Account) -> (),
	onExpired   : () -> (),
	onError     : ((string) -> ())?
)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	local code = session.code
	local secret = session.secret

	task.spawn(function()
		local elapsed = 0
		while elapsed < _POLL_TIMEOUT do
			task.wait(_POLL_INTERVAL)
			elapsed += _POLL_INTERVAL

			local ok, body = _post("/auth/link/status", {
				code = code,
				clientSecret = secret
			})

			if not ok then
				if onError then onError(body.error or "Network error") end
				return
			end

			local status: PollStatus = body.status

			if status == "AUTHORIZED" and body.token then
				local account: Account = {
					token = body.token,
					userId = tostring(body.userId),
					username = body.username or "unknown",
					addedAt = os.time(),
					lastUsed = os.time(),
				}
				_activeToken = body.token
				_activeAccount = account
				_upsertAccount(account)
				_persistActiveToken(body.token)
				_notifyState()

				if onAuthorized then
					onAuthorized(body.token, account)
				end

				return
			elseif status == "EXPIRED" or status == "CONSUMED" then
				if onExpired then
					onExpired()
				end
				return
			end
		end

		if onExpired then
			onExpired()
		end
	end)
end

function AccountsHandler.SetActiveToken(token: string)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")
	assert(type(token) == "string" and token ~= "", "[Nodeal] Invalid token.")

	_activeToken = token
	_activeAccount = nil

	local list = _loadAccounts()
	for _, acc in list do
		if acc.token == token then
			acc.lastUsed = os.time()
			_activeAccount = acc
			break
		end
	end
	_saveAccounts(list)
	_persistActiveToken(token)
	_notifyState()
end

function AccountsHandler.Logout(token: string?)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	local targetToken = token or _activeToken
	if not targetToken then return end

	task.spawn(function()
		_post("/account/tokens/revoke", {}, targetToken)
	end)

	local list = _loadAccounts()
	local newList = {}
	local wasActive = (targetToken == _activeToken)

	for _, acc in list do
		if acc.token ~= targetToken then
			table.insert(newList, acc)
		end
	end
	_saveAccounts(newList)

	if wasActive then
		if #newList > 0 then
			AccountsHandler.SetActiveToken(newList[1].token)
		else
			_activeToken = nil
			_activeAccount = nil
			_persistActiveToken(nil)
			_notifyState()
		end
	end
end

function AccountsHandler.GetActiveToken(): string?
	return _activeToken
end

function AccountsHandler.GetActiveAccount(): Account?
	return _activeAccount
end

function AccountsHandler.IsLoggedIn(): boolean
	return _activeToken ~= nil
end

function AccountsHandler.GetSavedAccounts(): { Account }
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	return _loadAccounts()
end

function AccountsHandler.RemoveAccount(token: string)
	AccountsHandler.Logout(token)
end

function AccountsHandler.ClearAll()
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	_plugin:SetSetting(_STORE_KEY, {})
	_activeToken = nil
	_activeAccount = nil
	_persistActiveToken(nil)
	_notifyState()
end

function AccountsHandler.UpdateUsername(token: string, username: string)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")

	local list = _loadAccounts()
	for _, acc in list do
		if acc.token == token then
			acc.username = username
			break
		end
	end
	_saveAccounts(list)
end

function AccountsHandler.FetchTokens(): (boolean, any)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")
	assert(_activeToken ~= nil, "[Nodeal] No active session.")

	return _get("/account/tokens", _activeToken)
end

function AccountsHandler.RevokeToken(tokenId: string): (boolean, any)
	assert(_plugin ~= nil, "[Nodeal] Call Init() first.")
	assert(_activeToken ~= nil, "[Nodeal] No active session.")
	assert(type(tokenId) == "string" and tokenId ~= "", "[Nodeal] Invalid tokenId.")

	return _delete("/account/tokens", { tokenId = tokenId }, _activeToken)
end

function AccountsHandler.GetAvatarUrl(userId: string|number, params: { [string]: any }?): string
	assert(userId ~= nil, "[Nodeal] userId is required.")

	return _buildAvatarUrl(userId, params)
end

function AccountsHandler.OnStateChanged(callback: (string?) -> ()): () -> ()
	table.insert(_onStateListeners, callback)

	return function()
		for i, fn in _onStateListeners do
			if fn == callback then
				table.remove(_onStateListeners, i)
				break
			end
		end
	end
end

return AccountsHandler