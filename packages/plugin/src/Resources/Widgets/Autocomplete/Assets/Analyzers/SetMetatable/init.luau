--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local SetMetatable = {}

--[=[
    Copies members from a source metatable to a target table in the parser AST.

    @param parser The current Parser instance.
    @param targetName The string identifier of the target table.
    @param metaName The string identifier of the metatable.
    @param visited Optional recursion guard to prevent cyclic dependencies.
]=]
function SetMetatable:CopyMembers(parser: any, targetName: string, metaName: string, visited: { [string]: boolean }?)
    if not (targetName and metaName) then return end
    if type(targetName) ~= "string" or type(metaName) ~= "string" then return end
    if targetName == metaName then return end

    local seen = visited or {}
    if seen[metaName] then return end
    seen[metaName] = true

    local targetTable = parser.tables[targetName]
    local metaTable = parser.tables[metaName]

    if not targetTable then
        targetTable = {}
        parser.tables[targetName] = targetTable
    end

    if metaTable then
        for key, value in metaTable do
            if type(key) == "string" and string.sub(key, 1, 2) == "__" then
                if targetTable[key] == nil then
                    targetTable[key] = value
                end
                continue
            end

            if targetTable[key] == nil then
                if type(value) == "table" then
                    local clonedItem = table.clone(value)
                    clonedItem.table = targetName
                    targetTable[key] = clonedItem
                else
                    targetTable[key] = value
                end
            end
        end
    end
end

--[=[
    Initializes the analyzer by registering the setmetatable call hook on the parser.

    @param parser The current Parser instance.
]=]
function SetMetatable:Init(parser: any)
    parser.metatableLinks = parser.metatableLinks or {}

    parser:OnCall("setmetatable", function(args, lineIndex)
        local line = parser.lines[lineIndex] or ""
        local targetName = args[1]
        local metaName = args[2]

        -- Support variable assignment: local varName = setmetatable(...)
        local assignedVar = line:match("([%w_]+)%s*=%s*setmetatable")
        if assignedVar and type(metaName) == "string" then
            if not targetName or targetName == "{}" or targetName == "table" or targetName == "self" then
                targetName = assignedVar
            end
        end

        if type(targetName) == "string" and type(metaName) == "string" then
            table.insert(parser.metatableLinks, { target = targetName, meta = metaName })
            self:CopyMembers(parser, targetName, metaName)
        end
    end)
end

--[=[
    Executes a post-parsing reconciliation pass to guarantee that all members
    declared on metatables after the setmetatable call are propagated to target tables.

    @param parser The current Parser instance.
]=]
function SetMetatable:Run(parser: any)
    if not parser.metatableLinks or #parser.metatableLinks == 0 then return end

    for _, link in parser.metatableLinks do
        local visited = { [link.target] = true }
        self:CopyMembers(parser, link.target, link.meta, visited)

        local indexRef = parser.source:match(link.meta .. "%.__index%s*=%s*([%w_]+)")
        if indexRef and indexRef ~= "function" and indexRef ~= link.meta and parser.tables[indexRef] then
            self:CopyMembers(parser, link.target, indexRef, visited)
        end
    end
end

return SetMetatable
