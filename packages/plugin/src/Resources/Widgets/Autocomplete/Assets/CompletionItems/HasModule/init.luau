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

	detail = "HasModule(className: string, loaded: boolean?): boolean",
	documentation = "Returns true if the requested module exists."
}

--// Args //--
CompletionItem.args = {
	function(calling: ModuleScript)
		local result = {}
		local origin_context = utils.module.get_context(calling)

		for name: string, item: {[string]: any} in Autocomplete.ModulesCompletions do
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
					or `Check if the module {completion.label} exists.` 
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
	end,
	function()
		return {
			{
				label = "true",
				kind = Enum.CompletionItemKind.Keyword,
				detail = "true",
				documentation = { value = "Only returns true if the module is also fully loaded in memory." },
			},
			{
				label = "false",
				kind = Enum.CompletionItemKind.Keyword,
				detail = "false",
				documentation = { value = "Returns true even if the module is just registered but not loaded." },
			}
		}
	end
}

return CompletionItem
