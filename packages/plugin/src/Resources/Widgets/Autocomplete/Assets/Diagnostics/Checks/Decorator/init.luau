--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Check = {}

function Check.run(state: any): ()
	-- Pendant l'indexation initiale, un decorateur defini par un module pas encore vu
	-- ressemblerait a une faute de frappe.
	if not state.ready then
		return
	end

	for _, decorator in ipairs(state.scanned.decorators) do
		if state.isDecorator(decorator.name) then
			continue
		end

		state.report(decorator.line, decorator.character, decorator.character + #decorator.name, {
			code = "Nodeal.UnknownDecorator",
			message = `Unknown Nodeal decorator '@{decorator.name}'. Check the spelling or register it with game:RegisterDecorator().`,
			severity = Enum.Severity.Warning,
		})
	end
end

return Check
