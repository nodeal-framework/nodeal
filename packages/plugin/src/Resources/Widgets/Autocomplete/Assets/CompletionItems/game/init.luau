local CompletionItem = {}

--// Requirements //--
local Classes = script.Parent.Classes
local ExpendedInstances = require(Classes.ExpendedInstances)

--// Completion //--
CompletionItem.completion = {
	default = true
}

--// Next //--
CompletionItem.next = ExpendedInstances:Extand(script:GetChildren())

return CompletionItem
