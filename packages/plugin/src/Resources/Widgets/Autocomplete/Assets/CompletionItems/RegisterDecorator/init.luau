local CompletionItem = {}

CompletionItem.type = "function"
CompletionItem.methodes = { ":" }

--// Completion //--
CompletionItem.completion = {
	kind = Enum.CompletionItemKind.Function,

	detail = "RegisterDecorator(name: string, wrapper: (context: any, func: (...any) -> ...any, ...any) -> (...any) -> ...any): ()",
	documentation = "Register a new decorator in the global environment.",
	tags = { Enum.CompletionItemTag.PutCursorInParens },
}

--// Context Members (available on wrapper context parameter) //--
local contextMembers = {}

-- Properties --
contextMembers.Name = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Name: string",
		documentation = "The name of the decorator as declared in the annotation comment (e.g. \"command\" or \"route\").",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Arguments = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Arguments: { any }",
		documentation = "Array of arguments passed to the decorator inside the annotation comment (e.g. @decorator(arg1, arg2)).",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Parent = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Parent: any?",
		documentation = "The parent context if this decorator is semantically indented under another decorator, or nil if top-level.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
	next = function()
		return contextMembers
	end,
}

contextMembers.Children = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Children: { any }",
		documentation = "Array of raw child decorator definitions attached under this decorator in the AST.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Instance = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Instance: any?",
		documentation = "The instance or Node object containing the decorated method.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Method = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Method: string",
		documentation = "The name of the method being decorated.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Ancestors = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Ancestors: { any }",
		documentation = "List of ancestor decorator definitions. Allows indexing the context directly as context[1], context[2], etc.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.OriginalFunction = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "OriginalFunction: (...any) -> ...any",
		documentation = "The raw, undecorated function prior to any decorator wrappers.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.WrappedFunction = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "WrappedFunction: (...any) -> ...any",
		documentation = "The function resulting from previously applied inner decorators in the execution chain.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

contextMembers.Content = {
	methodes = { "." },
	completion = {
		kind = Enum.CompletionItemKind.Property,
		detail = "Content: { [any]: any }?",
		documentation = "Table containing raw parsed AST / comment block content.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context",
	},
}

-- Methods --
contextMembers.GetChildren = {
	type = "function",
	methodes = { ":" },
	completion = {
		kind = Enum.CompletionItemKind.Method,
		detail = "GetChildren(): { any }",
		documentation = "Returns an array of child decorator context objects that were semantically indented under this decorator.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context#GetChildren",
		tags = { Enum.CompletionItemTag.PutCursorInParens },
	},
	arguments = {},
}

contextMembers.FindFirstChild = {
	type = "function",
	methodes = { ":" },
	completion = {
		kind = Enum.CompletionItemKind.Method,
		detail = "FindFirstChild(name: string): any?",
		documentation = "Finds the first child decorator context matching the given name.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context#FindFirstChild",
		tags = { Enum.CompletionItemTag.PutCursorInParens },
	},
	arguments = {
		{ name = "name", type = "string" },
	},
	next = function()
		return contextMembers
	end,
}

contextMembers.IsDescendantOf = {
	type = "function",
	methodes = { ":" },
	completion = {
		kind = Enum.CompletionItemKind.Method,
		detail = "IsDescendantOf(parentName: string): boolean",
		documentation = "Returns true if this decorator context is nested within a decorator named parentName.",
		learnMoreLink = "https://www.nodeal.dev/references/decorator-context#IsDescendantOf",
		tags = { Enum.CompletionItemTag.PutCursorInParens },
	},
	arguments = {
		{ name = "parentName", type = "string" },
	},
}

CompletionItem.context = contextMembers

--// Arguments //--
CompletionItem.arguments = {
	{
		name = "name",
		type = "string"
	},
	{
		name = "wrapper",
		type = {
			kind = "function",
			arguments = {
				{ name = "context", type = "any", members = contextMembers },
				{ name = "func", type = "any" },
				{ name = "...", isVariadic = true, type = "any" }
			}
		}
	}
}

--// Args //--
CompletionItem.args = {
	nil,
	{
		{
			label = "function(context, func, ...)",
			kind = Enum.CompletionItemKind.Snippet,
			detail = "(context: any, func: (...any) -> ...any, ...any)",
			documentation = {
				value = "The decorator wrapper function receiving the invocation context."
			},
			insertText = "function(context, func, ...)\n\t\nend"
		}
	}
}

return CompletionItem
