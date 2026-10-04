local CompletionItem = {}

-- Services --
local CollectionService = game:GetService("CollectionService")

-- Constants --
local Assets = script.Parent.Parent.Parent
local Resources = Assets.Parent.Parent.Parent

-- Modules --
local Autocomplete = require(Assets.Parent.Autocomplete)
local utils = require(Resources.Modules.Utils)

--// Completion //--
CompletionItem.methodes = { ":" }

CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "GetService(className: string, overwrite: boolean?): Instance",
	documentation = "Returns the service with the requested name, or a pointer if it does not exist.",

	learnMoreLink = "https://create.roblox.com/docs/reference/engine/classes/ServiceProvider#GetService"
}

--// Args //--
CompletionItem.args = {
	function(calling: ModuleScript)
		local result = {}

		local origin_context = utils.module.get_context(calling)

		for name: string, item: {[string]: any} in Autocomplete.ServicesCompletions do
			local completion = item.completion
			local cache = {}

			local target = item.discovery.module
			if target == calling then continue end
			local target_context = utils.module.get_context(target)

			if not utils.module.is_module_accessible(origin_context, target_context, item) then continue end

			cache.label = completion.label
			cache.kind = completion.kind

			cache.detail = completion.detail
			cache.documentation = {
				value = completion.documentation
					or `Return a pointer to the content of {completion.label} service.` 
			}

			cache.codeSample = completion.example or nil

			if item.completion.tags then -- TODO update to work with the new ancestor structure of decorators
				local tags = {}
				for tag: string, _ in item.completion.tags do
					table.insert(tags, tag)
				end
				cache.tags = tags
			end

			table.insert(result, cache)
		end

		return result
	end
}

--// Next //--
CompletionItem.next = function(name: string): { [string]: any }
	local completion = Autocomplete.ServicesCompletions[name]
	if not completion or not completion.next then return {} end

	return completion.next
end

return CompletionItem
