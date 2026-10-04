--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Services //--
local ScriptEditorService = game:GetService("ScriptEditorService")

--// Constants //--
local Resources = script.Parent.Parent.Parent
local Modules = Resources.Modules

local Widget = script.Parent
local Assets = Widget.Assets

local accounts_menu = nil

local plugin_widget: {}
local plugin: plugin
local class

local dock: typeof(script.Parent.Assets.Ui)

--// Modules //--
local AccountsHandler = require(Modules.AccountsHandler)

--// Variables //--
local last_account_pfp_id
local accounts_action = {}

--// Private //--
local function dockResizeUpdate()
	local container = dock.Container
end

local function updateIcon(_, account)
	if account and last_account_pfp_id == account.userId then return end
	
	plugin_widget.button.Icon = account and AccountsHandler.GetAvatarUrl(account.userId) or Widget.Icon.ColorMapContent.Uri
	last_account_pfp_id = account and account.userId or nil
end

--// Public //--
local Accounts = {}

function Accounts.Clicked(self: any, widget: string)
	local ActiveAccount = AccountsHandler.GetActiveAccount()
	
	if AccountsHandler.IsLoggedIn() then
		accounts_menu:Clear()
		local accounts = AccountsHandler.GetSavedAccounts()

		for _, account in accounts do
			if account.userId == ActiveAccount.userId then continue end
			local account_action = accounts_action[account.userId]
			
			if not account_action then
				account_action = accounts_menu:AddNewAction(account.token, account.username)
				accounts_action[account.userId] = account_action
			else
				accounts_menu:AddAction(account_action)
			end
		end
		
		accounts_menu:AddSeparator()
		
		if not accounts_action["nd_login"] then
			accounts_action["nd_login"] = accounts_menu:AddNewAction("nd_login", "Login")
		else
			accounts_menu:AddAction(accounts_action["nd_login"])
		end
		
		if not accounts_action["nd_logout"] then
			accounts_action["nd_logout"] = accounts_menu:AddNewAction("nd_logout", "Logout")
		else
			accounts_menu:AddAction(accounts_action["nd_logout"])
		end
		
		local action = accounts_menu:ShowAsync()
		if action then
			if string.find(action.ActionId, "nd_login") then
				dock.Enabled = true
			elseif string.find(action.ActionId, "nd_logout") then
				AccountsHandler.Logout()
			else
				for _, account in accounts do
					if string.find(action.ActionId, account.token) then
						AccountsHandler.SetActiveToken(account.token)
						break
					end
				end
			end
		end
	else
		dock.Enabled = not dock.Enabled
	end
end

function Accounts.Init(self: any, widget: string)
	class = self
	plugin = class.plugin
	
	plugin_widget = self.widgets[widget]
	dock = plugin_widget.dock
	
	accounts_menu = plugin:CreatePluginMenu("Nodeal:Accounts:Selection", "Account Selection")

	task.delay(0.25, function() -- TODO This should be changed
		AccountsHandler.OnStateChanged(updateIcon)
		updateIcon(nil, AccountsHandler.GetActiveAccount())
	end)
	
	dock.Container.Body.TextButton.MouseButton1Click:Connect(function()
		local success, session = AccountsHandler.InitLink()
		
		if success then
			AccountsHandler.PollLinkStatus(session, function()
				dock.Enabled = false
			end)
			
			print("Ouvrez cette URL : " .. session.url)
			print("Code de vérification : " .. session.code)
		else
			warn("Erreur d'initialisation :", session.error)
		end
	end)
	
	dock:GetPropertyChangedSignal("AbsoluteSize"):Connect(dockResizeUpdate)
	dockResizeUpdate()
end

return Accounts
