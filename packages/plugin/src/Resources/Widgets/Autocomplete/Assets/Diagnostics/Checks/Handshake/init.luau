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

-- L'orchestrateur a deja ecarte tout ce qui n'est pas un module Nodeal : ici on ne traite que
-- les handshakes commences mais incomplets ou mal termines.
function Check.run(state: any): ()
	local accessor = state.accessor

	if not accessor then
		state.report(1, 1, 1, {
			code = "Nodeal.MissingHandshake",
			message = "Nodeal module is missing its security accessor. Add 'local __ = _G()' before registering the module.",
			severity = Enum.Severity.Error,
		})

		return
	end

	local scanned = state.scanned
	local returns = {}
	local complete = false

	for index, line in ipairs(scanned.code) do
		local call = line:match("return%s+([%w_]+)%s*%(")

		if call == accessor then
			complete = true
		end

		if line:match("^return[%s;]") or line:match("^return$") then
			table.insert(returns, index)
		end
	end

	if complete then
		return
	end

	if #returns == 0 then
		local lineIndex = #scanned.lines

		while lineIndex > 1 do
			local text = scanned.lines[lineIndex] or ""

			if text:match("%S") then
				break
			end

			lineIndex -= 1
		end

		local lastText = scanned.lines[lineIndex] or ""

		state.report(lineIndex, 1, math.max(#lastText, 1), {
			code = "Nodeal.IncompleteHandshake",
			message = `Nodeal module never completes its handshake. End the file with 'return {accessor}(YourModule)'.`,
			severity = Enum.Severity.Error,
		})

		return
	end

	local lineIndex = returns[#returns]

	state.report(lineIndex, 1, 6, {
		code = "Nodeal.IncompleteHandshake",
		message = `This return bypasses the Nodeal handshake. Use 'return {accessor}(YourModule)' so the module gets registered.`,
		severity = Enum.Severity.Error,
	})
end

return Check
