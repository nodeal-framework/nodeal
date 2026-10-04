--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local function _disconnect(tbl: { [any]: any? })
	for index: any, connection: RBXScriptConnection | table in tbl do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
			tbl[index] = nil
		elseif typeof(connection) == "table" and connection ~= tbl then
			_disconnect(connection)
		end
	end
end

--// Connector //--
local Connector = {}
Connector.__index = Connector

function Connector:Track(item: RBXScriptSignal | typeof(Connector), promise: (...any?) -> (), index: any?)
	if typeof(item) == "RBXScriptSignal" then
		item = item:Connect(promise)
	end
	
	if index == nil then
		table.insert(self, item)
	else
		self[index] = item
	end
end

function Connector:Disconnect(index: any?): boolean
	if index ~= nil then
		local item = self[index]

		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
			self[index] = nil
			
			return true
		elseif type(item) == "table" and type(item.Disconnect) == "function" then
			item:Disconnect()
			self[index] = nil
			
			return true
		end

		return false
	else
		for key: any, item: any in self do
			if typeof(item) == "RBXScriptConnection" then
				item:Disconnect()
			elseif type(item) == "table" and type(item.Disconnect) == "function" and item ~= self then
				item:Disconnect()
			end

			self[key] = nil
		end

		return true
	end
end

function Connector:Destroy()
	self:Disconnect()
	setmetatable(self, nil)
end

--// Controller //--
local ConnectionController = {}

function ConnectionController.new()
	return setmetatable({}, Connector)
end

return ConnectionController