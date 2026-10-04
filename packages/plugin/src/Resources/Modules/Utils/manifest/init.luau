--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

type ManifestType = {
	TagRoot: string
}

if game:GetService("RunService"):IsRunning() then return {} end

local Manifest = game:GetService("ReplicatedStorage").Global.Manifest

local methodes = {}
methodes.__index = function(self, index: string): any
	return Manifest:GetAttribute(index)
end

return setmetatable({}, methodes) :: ManifestType