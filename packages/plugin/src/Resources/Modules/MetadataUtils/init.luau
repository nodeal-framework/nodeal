--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local MetadataUtils = {}

function MetadataUtils.find(metadata: { [number]: any }, key: string): number?
	if type(metadata) ~= "table" then return nil end
	for i, v in metadata do
		if type(v) == "table" and v[1] == key then
			return i
		end
	end
	
	return nil
end

function MetadataUtils.new(metadata: { [number]: any }, key: string, ...): ()
	if type(metadata) ~= "table" then return end
	if MetadataUtils.find(metadata, key) then return end
	
	metadata[#metadata + 1] = {key, {...}}
end

function MetadataUtils.get(metadata: { [number]: any }, key: string): { [number]: any }?
	if type(metadata) ~= "table" then return nil end
	local index = MetadataUtils.find(metadata, key)
	
	if index and type(metadata[index]) == "table" then
		return metadata[index][2]
	end
	
	return nil
end

function MetadataUtils.set(metadata: { [number]: any }, key: string, ...): ()
	if type(metadata) ~= "table" then return end
	local index = MetadataUtils.find(metadata, key)
	
	if index and type(metadata[index]) == "table" then
		metadata[index][2] = {...}
	else
		MetadataUtils.new(metadata, key, ...)
	end
end

return MetadataUtils