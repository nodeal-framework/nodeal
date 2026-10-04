--[[
    © 2026 Nodeal. All rights reserved.

    This source code is open-source and free for modification and use in your projects.
    However, you may not sell, sublicense, or distribute this framework (or 
    any rebranded version of it) as a standalone product.

    Any public use or redistribution of this module requires this header 
    to remain intact in the source code. For the complete license terms, 
    please visit: https://www.nodeal.dev/license
]]

local Snippet = {}

Snippet.prefix = "!"

function Snippet.provide(): { any }
	return {
		{
			label = "--[=[ ]=]",
			kind = Enum.CompletionItemKind.Snippet,
			preselect = true,
			detail = "Documentation block that can contain documentation and interpreted decorators.",
			documentation = { value = "Documentation block that can contain documentation and interpreted decorators." },
			codeSample = "--[=[\n    Documentation block\n\n    @async\n    @typecheck\n]=]",
			newText = "--[=[\n\t\n]=]",
		},
	}
end

return Snippet
