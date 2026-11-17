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

local Pattern = "(require%s*%(%s*[\"'])([^\"']+)"
local Href = "https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#require"

local Check = {}

function Check.run(state: any): ()
	if not state.ready then
		return
	end

	local modules = state.modules
	local services = state.services

	for index, line in ipairs(state.scanned.code) do
		Scanner.forEachCall(line, Pattern, function(character: number, name: string): ()
			if state.declared[name] or modules[name] or services[name] then
				return
			end

			state.report(index, character, character + #name - 1, {
				code = "Nodeal.UnresolvedRequire",
				message = `require("{name}") does not match any registered Nodeal module or service.`,
				severity = Enum.Severity.Error,
				codeDescription = {
					href = Href,
				},
			})
		end)
	end
end

return Check
