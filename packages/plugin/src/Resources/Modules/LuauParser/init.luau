--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local parser = {}

for _, module: ModuleScript in script:GetChildren() do
	if not module:IsA("ModuleScript") then continue end

	local content = require(module)
	if content.Init then
		content.Init(parser)
		content.Init = nil
	end

	parser[module.Name] = content
end

return parser