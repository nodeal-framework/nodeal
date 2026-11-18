--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Constants //--
local Scanner = require(script.Parent.Parent.Scanner)

local Pattern = Scanner.Patterns.GetService
local Href = "https://create.roblox.com/docs/reference/engine/classes/DataModel#GetService"

-- Un service natif est valide pour toujours ; un nom absent peut encore etre enregistre plus
-- tard par un module, donc seul le resultat positif est memorise.
local NativeServices: { [string]: boolean } = {}

local function isNativeService(name: string): boolean
	if NativeServices[name] then
		return true
	end

	local success, service = pcall(game.GetService, game, name)

	if success and service then
		NativeServices[name] = true
		return true
	end

	return false
end

local Check = {}

function Check.run(state: any): ()
	local services = state.services
	local modules = state.modules

	-- Plusieurs services d'un meme fichier partagent le meme contexte : on ne relit pas les
	-- attributs a chaque appel.
	local originContext: { string }? = nil
	local providerContexts: { [Instance]: { string } } = {}

	for index, line in ipairs(state.scanned.code) do
		Scanner.forEachCall(line, Pattern, function(character: number, name: string): ()
			if state.declared[name] then
				return
			end

			if modules[name] and not services[name] then
				state.report(index, character, character + #name - 1, {
					code = "Nodeal.WrongLookup",
					message = `'{name}' is a Nodeal module, not a service. Use game:GetModule("{name}") instead.`,
					severity = Enum.Severity.Warning,
				})

				return
			end

			local item = services[name]

			if item then
				if not state.ready or not state.target then
					return
				end

				local provider = item.discovery and item.discovery.module

				if not provider or not provider.Parent then
					return
				end

				local origin = originContext

				if not origin then
					origin = state.utils.module.get_context(state.target)
					originContext = origin
				end

				local targetContext = providerContexts[provider]

				if not targetContext then
					targetContext = state.utils.module.get_context(provider)
					providerContexts[provider] = targetContext
				end

				if #origin == 0 or #targetContext == 0 then
					return
				end

				if state.utils.module.is_module_accessible(origin, targetContext, item) then
					return
				end

				state.report(index, character, character + #name - 1, {
					code = "Nodeal.ContextMismatch",
					message = `Service '{name}' is not available in the {table.concat(origin, "/")} context.`,
					severity = Enum.Severity.Warning,
				})

				return
			end

			if isNativeService(name) or not state.ready then
				return
			end

			state.report(index, character, character + #name - 1, {
				code = "Nodeal.UnknownService",
				message = `Unknown service '{name}'. No Nodeal service or Roblox service has this name.`,
				severity = Enum.Severity.Error,
				codeDescription = {
					href = Href,
				},
			})
		end)
	end
end

return Check
