--// Constants //--
local Handlers = script.Parent.Handlers

--// Script //--
local pluginClass = require(Handlers.PluginHandler)(plugin)
require(Handlers.WidgetsHandler)(pluginClass)
require(Handlers.ThemesHandler)(pluginClass)
require(Handlers.TagFunctions)(pluginClass)