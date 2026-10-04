--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Table = {}

local utils

function Table.ensure<key>(tbl: { [key]: any }, ...: key): { [key]: any }
	for i = 1, select("#", ...) do
		local key = select(i, ...)

		if tbl[key] == nil then
			tbl[key] = {}
		end
	end

	return tbl
end

function Table.Init(_utils: { [string]: { [string]: (any) -> (any) } }): ()
	utils = _utils
end

return Table