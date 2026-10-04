local CompletionItem = {}

-- Constants --
local Assets = script.Parent.Parent.Parent
local Resources = Assets.Parent.Parent.Parent

-- Modules --
local Autocomplete = require(Assets.Parent.Autocomplete)
local utils = require(Resources.Modules.Utils)

CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "GetModule(className: string): any",
	documentation = "Return a pointer to the content of the requested module."
}

--// Args //--
CompletionItem.args = {
	function(calling: ModuleScript)
		local result = {}
		local origin_context = utils.module.get_context(calling)

		for _: string, item: {[string]: any} in Autocomplete.ModulesCompletions do
			local completion = item.completion
			local cache = {}

			local target = item.discovery and item.discovery.module
			if target == calling then continue end
			if target and not target.Parent then continue end

			local target_context = target and utils.module.get_context(target) or {}

			if not utils.module.is_module_accessible(origin_context, target_context, item) then continue end

			if completion.hidden then continue end

			cache.label = completion.label
			cache.kind = completion.kind

			cache.detail = completion.detail
			cache.documentation = {
				value = completion.documentation 
					or `Return a pointer to the content of {completion.label} module.` 
			}

			cache.codeSample = completion.example or completion.codeSample or nil

			if completion.tags then
				local tags = {}
				for tag: string, _ in completion.tags do
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
	local completion = Autocomplete.ModulesCompletions[name]
	if not completion or not completion.next then return {} end

	return completion.next
end

return CompletionItem
