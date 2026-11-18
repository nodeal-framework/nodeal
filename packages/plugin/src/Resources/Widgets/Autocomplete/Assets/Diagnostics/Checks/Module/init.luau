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

local Pattern = Scanner.Patterns.GetModule

local Check = {}

function Check.run(state: any): ()
	local modules = state.modules
	local services = state.services

	for index, line in ipairs(state.scanned.code) do
		Scanner.forEachCall(line, Pattern, function(character: number, name: string): ()
			if state.declared[name] or modules[name] then
				return
			end

			if services[name] then
				state.report(index, character, character + #name - 1, {
					code = "Nodeal.WrongLookup",
					message = `'{name}' is a Nodeal service, not a module. Use game:GetService("{name}") instead.`,
					severity = Enum.Severity.Warning,
				})

				return
			end

			if not state.ready then
				return
			end

			state.report(index, character, character + #name - 1, {
				code = "Nodeal.UnknownModule",
				message = `Unknown module '{name}'. No Nodeal module with this name is indexed.`,
				severity = Enum.Severity.Error,
			})
		end)
	end
end

return Check
