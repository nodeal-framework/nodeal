--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this framework requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local DependencyGraph = {}
DependencyGraph.__index = DependencyGraph

export type GraphNode = {
	module: ModuleScript,
	dependencies: { [ModuleScript]: string }, -- module -> type (e.g., "require", "GetService")
	dependents: { [ModuleScript]: boolean },
	inDegree: number,
}

function DependencyGraph.new()
	local self = setmetatable({}, DependencyGraph)
	self.nodes = {} :: { [ModuleScript]: GraphNode }
	return self
end

function DependencyGraph:GetNode(module: ModuleScript): GraphNode
	if not self.nodes[module] then
		self.nodes[module] = {
			module = module,
			dependencies = {},
			dependents = {},
			inDegree = 0,
		}
	end
	return self.nodes[module]
end

function DependencyGraph:ClearDependencies(module: ModuleScript)
	local node = self.nodes[module]
	if not node then return end

	-- Remove this module from its providers' dependents list
	for provider, _ in node.dependencies do
		local provNode = self.nodes[provider]
		if provNode then
			provNode.dependents[module] = nil
		end
	end

	-- Reset dependencies and inDegree
	node.dependencies = {}
	node.inDegree = 0
end

function DependencyGraph:AddDependency(dependent: ModuleScript, provider: ModuleScript, type: string, isStrict: boolean)
	local depNode = self:GetNode(dependent)
	local provNode = self:GetNode(provider)

	-- We only track strict dependencies for topological sorting.
	if isStrict and dependent ~= provider then
		if not depNode.dependencies[provider] then
			depNode.dependencies[provider] = type
			provNode.dependents[dependent] = true
			depNode.inDegree += 1
		end
	end
end

function DependencyGraph:FilterExcludedNodes()
	-- Les retraits sont relevés d'abord et appliqués ensuite. Retirer pendant le parcours
	-- laissait des arêtes qui pointaient vers des nœuds déjà partis, et c'est sur elles que le
	-- tri se cassait plus loin.
	local doomed = {}

	for module, _ in self.nodes do
		if not module.Parent then
			table.insert(doomed, module)
		end
	end

	for _, module in doomed do
		local node = self.nodes[module]

		if not node then
			continue
		end

		-- Nodeal Module 'dependent' depends on Excluded Module 'module'
		for dependent, _ in node.dependents do
			local dependentNode = self.nodes[dependent]
			if dependentNode and dependentNode.dependencies[module] then
				dependentNode.dependencies[module] = nil
				dependentNode.inDegree -= 1
			end
		end

		-- Excluded Module 'module' depends on 'provider'
		for provider, _ in node.dependencies do
			local providerNode = self.nodes[provider]
			if providerNode then
				providerNode.dependents[module] = nil
			end
		end

		self.nodes[module] = nil
	end
end

-- Uses Kahn's algorithm for topological sorting
function DependencyGraph:ResolveExecutionOrder(roots: {Instance}?): ({ ModuleScript }, string?)
	local order = {}
	local queue = {}

	local includedNodes = {}

	for module, node in self.nodes do
		local isNodeal = false
		if module.Parent and not module:GetAttribute("ContentExcluded") then
			if roots then
				for _, root in roots do
					if module:IsDescendantOf(root) then
						isNodeal = true
						break
					end
				end
			else
				isNodeal = true
			end
		end

		if isNodeal then
			includedNodes[module] = node
		end
	end

	local inDegrees = {}
	for module, node in includedNodes do
		local currentInDegree = 0
		for provider, _ in node.dependencies do
			if includedNodes[provider] then
				currentInDegree += 1
			end
		end
		inDegrees[module] = currentInDegree
	end

	for module, inDegree in inDegrees do
		if inDegree == 0 then
			table.insert(queue, module)
		end
	end

	table.sort(queue, function(a, b) return a.Name < b.Name end)

	local head = 1
	local processedCount = 0
	local queued = {}
	for _, module in queue do queued[module] = true end

	local totalNodes = 0
	for _, _ in includedNodes do totalNodes += 1 end

	local hadCycle = false

	while processedCount < totalNodes do
		if head > #queue then
			-- Stalled on a cycle: release one blocked module only, so modules that merely depend
			-- on the cycle still load after all of it (appending every leftover in hash order
			-- could load a dependent before its provider).
			hadCycle = true

			local pick = self:PickCycleBreaker(includedNodes, inDegrees, queued)

			if not pick then break end

			queued[pick] = true
			table.insert(queue, pick)
		end

		local current = queue[head]
		head += 1

		table.insert(order, current)
		processedCount += 1

		local node = self.nodes[current]
		if not node then
			continue
		end

		local newReady = {}
		for dependent, _ in node.dependents do
			if includedNodes[dependent] then
				inDegrees[dependent] -= 1
				if inDegrees[dependent] == 0 and not queued[dependent] then
					table.insert(newReady, dependent)
				end
			end
		end

		if #newReady > 0 then
			table.sort(newReady, function(a, b) return a.Name < b.Name end)
			for _, dep in newReady do
				queued[dep] = true
				table.insert(queue, dep)
			end
		end
	end

	if hadCycle then
		local cyclePath, isUnresolvable = self:FindCycleTrace(includedNodes)

		if isUnresolvable then
			warn("[Nodeal] Critical Warning: Unresolvable circular dependency detected. This will likely crash at runtime.\nTrace: " .. (cyclePath or "unknown"))
		end
	end

	return order, nil
end

-- Picks the module to release when Kahn stalls: it must sit in a cycle whose remaining providers
-- are all inside that same cycle, otherwise a module could load before a provider it waits on.
function DependencyGraph:PickCycleBreaker(includedNodes: { [ModuleScript]: any }, inDegrees: { [ModuleScript]: number }, queued: { [ModuleScript]: boolean }): ModuleScript?
	local index, lowLink, onStack, stack = {}, {}, {}, {}
	local componentOf = {}
	local components = {}
	local counter = 0

	-- Tarjan over the modules still blocked (edges go dependent -> provider)
	local function strongConnect(module: ModuleScript)
		counter += 1
		index[module] = counter
		lowLink[module] = counter
		table.insert(stack, module)
		onStack[module] = true

		for provider, _ in self.nodes[module].dependencies do
			if includedNodes[provider] and not queued[provider] then
				if not index[provider] then
					strongConnect(provider)
					lowLink[module] = math.min(lowLink[module], lowLink[provider])
				elseif onStack[provider] then
					lowLink[module] = math.min(lowLink[module], index[provider])
				end
			end
		end

		if lowLink[module] == index[module] then
			local component = {}
			repeat
				local member = table.remove(stack)
				onStack[member] = nil
				componentOf[member] = component
				table.insert(component, member)
			until member == module
			table.insert(components, component)
		end
	end

	for module, _ in includedNodes do
		if not queued[module] and not index[module] then
			strongConnect(module)
		end
	end

	local pick = nil

	for _, component in components do
		local isSource = true

		for _, member in component do
			for provider, _ in self.nodes[member].dependencies do
				if includedNodes[provider] and not queued[provider] and componentOf[provider] ~= component then
					isSource = false
					break
				end
			end
			if not isSource then break end
		end

		if isSource then
			for _, member in component do
				if not pick or inDegrees[member] < inDegrees[pick] or (inDegrees[member] == inDegrees[pick] and member.Name < pick.Name) then
					pick = member
				end
			end
		end
	end

	return pick
end

function DependencyGraph:FindCycleTrace(includedNodes: { [ModuleScript]: any }): (string?, boolean?)
	local visited = {}
	local stack = {}
	local path = {}

	local function dfs(module: ModuleScript): (string?, boolean?)
		if stack[module] then
			-- Found cycle!
			local trace = ""
			local inCycle = false
			local isUnresolvable = true

			for i, m in path do
				if m == module then inCycle = true end
				if inCycle then
					trace ..= m.Name .. " -> "

					local nextModule = path[i+1] or module
					local mNode = self.nodes[m]
					if mNode and mNode.dependencies[nextModule] ~= "require" then
						isUnresolvable = false
					end
				end
			end
			trace ..= module.Name
			return trace, isUnresolvable
		end

		if visited[module] then return nil, false end

		visited[module] = true
		stack[module] = true
		table.insert(path, module)

		local node = self.nodes[module]
		for provider, _ in node.dependencies do
			if includedNodes[provider] then
				local cycle, unresolv = dfs(provider)
				if cycle then return cycle, unresolv end
			end
		end

		stack[module] = false
		table.remove(path)
		return nil, false
	end

	for module, _ in includedNodes do
		if not visited[module] then
			local cycle, unresolv = dfs(module)
			if cycle then return cycle, unresolv end
		end
	end
	return "Unknown Cycle", false
end

return DependencyGraph
