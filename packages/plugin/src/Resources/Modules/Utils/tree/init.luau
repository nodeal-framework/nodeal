--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local utils, Tree = nil, {}

local CollectionService = game:GetService("CollectionService")

function Tree.FindFirstAncestorWithTag(instance: Instance, tag: string | {string}): Instance?
	local current = instance.Parent

	while current and current ~= game do
		if typeof(tag) == "table" then
			for _, tagName in tag do
				if CollectionService:HasTag(current, tagName) then
					return current
				end
			end
		else
			if CollectionService:HasTag(current, tag) then
				return current
			end
		end

		current = current.Parent
	end

	return nil
end

function Tree.Init(_utils: { [string]: { [string]: (any) -> (any) } }): ()
	utils = _utils
end

return Tree