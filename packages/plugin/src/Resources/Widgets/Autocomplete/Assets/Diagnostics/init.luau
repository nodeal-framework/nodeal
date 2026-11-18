--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

--// Constants //--
local Resources = script.Parent.Parent.Parent.Parent

local ScriptEditorService = game:GetService("ScriptEditorService")

local utils = require(Resources.Modules.Utils)
local Scanner = require(script.Scanner)

local Id = "Nodeal.Diagnostics"
local Priority = 255

--// Types //--
type Position = { line: number, character: number }

type Range = {
	start: Position,
	["end"]: Position,
}

type Diagnostic = {
	range: Range,
	code: string?,
	message: string,
	severity: Enum.Severity?,
	codeDescription: { href: string }?,
}

export type Context = {
	isReady: () -> boolean,
	getServices: () -> { [string]: any },
	getModules: () -> { [string]: any },
	isDecorator: (name: string) -> boolean,
}

--// Checks //--
local Checks = {}
local FailedChecks: { [string]: boolean } = {}

for _, module: ModuleScript in script.Checks:GetChildren() do
	if not module:IsA("ModuleScript") then continue end

	local check = require(module)
	local run = if type(check) == "function" then check else check.run

	if type(run) == "function" then
		table.insert(Checks, {
			name = module.Name,
			run = run,
		})
	end
end

--// Module //--
local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics.new(context: Context)
	return setmetatable({
		context = context,
	}, Diagnostics)
end

function Diagnostics:isTracked(instance: Instance): boolean
	local current: Instance? = instance

	while current do
		if current:HasTag(utils.manifest.TagRoot) then
			return true
		end

		current = current.Parent
	end

	return false
end

function Diagnostics:getSource(target: LuaSourceContainer): string?
	local success, source = pcall(function()
		return ScriptEditorService:GetEditorSource(target)
	end)

	if success and type(source) == "string" then
		return source
	end

	local fallbackSuccess, fallback = pcall(function()
		return target.Source
	end)

	if fallbackSuccess then
		return fallback
	end

	return nil
end

-- Les verifications ne concernent que les modules Nodeal, pas tous les scripts du TagRoot. On
-- les reconnait a leur accesseur ou a leurs decorateurs ; ContentHeader couvre le module dont
-- le handshake est casse mais que l'indexeur a deja vu (il a un contenu sans accesseur).
local function isNodealModule(target: Instance, accessor: string?, decoratorCount: number): boolean
	if accessor or decoratorCount > 0 then
		return true
	end

	local success, header = pcall(function()
		return target:GetAttribute("ContentHeader")
	end)

	return success and header ~= nil
end

function Diagnostics:analyze(source: string, target: Instance?): { Diagnostic }
	local scanned = Scanner.scan(source)
	local accessor = Scanner.findAccessor(scanned.code)

	if target then
		if not target:IsA("ModuleScript") then
			return {}
		end

		if not isNodealModule(target, accessor, #scanned.decorators) then
			return {}
		end
	end

	local diagnostics = {}

	local state = {
		report = function(line: number, startCharacter: number, endCharacter: number, config: any): ()
			table.insert(diagnostics, {
				range = {
					start = {
						line = line,
						character = startCharacter,
					},
					-- Les positions passees par les checks sont inclusives (dernier caractere
					-- souligne). Studio attend une fin exclusive : sans ce +1, le dernier
					-- caractere du nom n'est jamais surligne.
					["end"] = {
						line = line,
						character = endCharacter + 1,
					},
				},
				code = config.code,
				message = config.message,
				severity = config.severity,
				codeDescription = config.codeDescription,
			})
		end,

		scanned = scanned,
		accessor = accessor,
		declared = Scanner.collectDeclared(scanned.code),

		ready = self.context.isReady(),
		services = self.context.getServices() or {},
		modules = self.context.getModules() or {},
		isDecorator = self.context.isDecorator,

		target = target,
		utils = utils,
	}

	for _, check in Checks do
		-- Une verification qui casse ne doit pas emporter les autres.
		local success, message = pcall(check.run, state)

		if not success and not FailedChecks[check.name] then
			FailedChecks[check.name] = true
			warn(`[Nodeal Diagnostics] {check.name} failed: {tostring(message)}`)
		end
	end

	return diagnostics
end

function Diagnostics:analyzeRequest(request: any): { Diagnostic }
	local target = request and request.script

	if not target or not target:IsA("LuaSourceContainer") then
		return {}
	end

	local trackedSuccess, tracked = pcall(function()
		return self:isTracked(target)
	end)

	if not trackedSuccess or not tracked then
		return {}
	end

	local source = self:getSource(target)

	if not source or source == "" then
		return {}
	end

	return self:analyze(source, target)
end

function Diagnostics:register(): ()
	pcall(function()
		ScriptEditorService:DeregisterScriptAnalysisCallback(Id)
	end)

	local callback = function(request: any)
		local success, diagnostics = pcall(function()
			return self:analyzeRequest(request)
		end)

		if success and diagnostics then
			return {
				diagnostics = diagnostics,
			}
		end

		return {
			diagnostics = {},
		}
	end

	-- Une version de Studio sans cette API ne doit pas emporter l'autocomplete avec elle.
	pcall(function()
		ScriptEditorService:RegisterScriptAnalysisCallback(Id, Priority, callback)
	end)
end

-- Re-enregistrer force Studio a relancer l'analyse : les diagnostics restes vides pendant
-- l'indexation initiale se remplissent sans attendre la prochaine frappe.
function Diagnostics:refresh(): ()
	self:register()
end

function Diagnostics:unregister(): ()
	pcall(function()
		ScriptEditorService:DeregisterScriptAnalysisCallback(Id)
	end)
end

return Diagnostics
