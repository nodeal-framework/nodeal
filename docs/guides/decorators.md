---
title: "Decorators"
description: "Exhaustive guide to Nodeal comment-based decorators: compile-time metadata, lifecycle triggers, context scoping, and custom decorator authoring."
category: "Modules"
order: 8
---

Nodeal features an advanced, compile-time metadata system powered by **comment-based decorators**.

By placing standard Luau block comments (`--[=[ ... ]=]`) directly above your function or module definitions, you can configure execution scopes, lifecycle triggers, IDE autocomplete behaviors, and static analysis collectors without adding runtime boilerplate.

---

## Syntax & Core Rules

Decorators are declared inside Luau block comments using the `@` prefix:

```luau
local __=_G() local CombatService = {}

--[=[
    Initiates an attack against a target player.

    @param targetPlayer The player taking damage.
    @param damageAmount Numeric damage value.
    @server
    @see https://www.nodeal.dev/docs
]=]
function CombatService:Attack(targetPlayer: Player, damageAmount: number): ()
    -- Implementation...
end

return __(CombatService)
```

### Argument Inference & Default Values
* **Implicit Truthy Values**: If a decorator accepting a boolean flag is declared without arguments, it defaults its first argument to `true`. For example, `@build` is equivalent to `@build true`, and `@server` is equivalent to `@server true`.
* **Explicit Disabling**: You can pass `false` to disable default lifecycle behaviors, such as `@init false` to prevent a function named `Init` from executing during the Ignition phase.
* **IntelliSense Parameter Placeholders**: In Studio's autocomplete popup, parameter indicators (e.g. `<priority: number>` or `<...name: string>`) display expected argument schemas.

---

## Decorators Index

Nodeal includes 18 built-in decorators categorized by architectural purpose:

> [!TIP]
> For exact signatures, parameters, and autocomplete schemas, visit the **[Decorators Technical Reference](../references/decorators)**.

### Context & Scoping
| Tag | Target | Description | Autocomplete Schema |
| :--- | :--- | :--- | :--- |
| **`@server`** | Both | Restricts method/module execution exclusively to the Server, or scopes child decorators. | `@server <active: boolean> \| <...decorator>` |
| **`@client`** | Both | Restricts method/module execution exclusively to the Client, or scopes child decorators. | `@client <active: boolean> \| <...decorator>` |
| **`@context`** | Decorator | Overrides visibility restrictions for IntelliSense (e.g. `*`, `client`, `server`). | `@context <...context: string>` |
| **`@hidden`** | Method | Hides the method from Studio autocomplete popups while keeping it callable. | `@hidden <hidden: boolean>` |

### Lifecycle & Scheduling
| Tag | Target | Description | Autocomplete Schema |
| :--- | :--- | :--- | :--- |
| **`@build`** | Method | Schedules a function to run immediately during the Build phase (module load). | `@build <active: boolean>` |
| **`@init`** | Method | Schedules a function to run during the Ignition phase (after all modules are loaded). | `@init <active: boolean>` |
| **`@priority`** | Module | Header decorator defining load priority order (lower numbers execute first). | `@priority <priority: number>` |

### Documentation & IntelliSense
| Tag | Target | Description | Autocomplete Schema |
| :--- | :--- | :--- | :--- |
| **`@param`** | Method | Documents a function parameter in the Studio hover tooltip. | `@param <name: string> [description: string]` |
| **`@return`** | Method | Documents the return value of a function in the Studio hover tooltip. | `@return [description: string]` |
| **`@yield`** | Method | Documents that a function yields, e.g. while waiting on a remote call. | `@yield [description: string]` |
| **`@see`** | Method | Embeds a clickable external documentation URL into the hover tooltip. | `@see <url: string>` |
| **`@example`** | Method | Embeds a syntax-highlighted code sample directly into the hover tooltip. | `@example <example: string>` |
| **`@alias`** | Method | Adds alternative alias names to a function in autocomplete. | `@alias <...name: string>` |
| **`@deprecated`** | Method | Flags a function as deprecated, applying a visual strikethrough in autocomplete. | `@deprecated <deprecated: boolean>` |
| **`@overloads`** | Method | Registers a count of overloaded signatures for Studio type introspection. | `@overloads <overloads: number>` |

### Metaprogramming & Custom Collectors
| Tag | Target | Description | Autocomplete Schema |
| :--- | :--- | :--- | :--- |
| **`@collect`** | Registration | Instructs the Pre-Parser to collect all decorated functions into `.collected`. | `@collect` |
| **`@export`** | Registration | Activates dynamic metadata extractors (`arguments`, `returns`, `usages`, etc.). | `@export <...export: string>` |
| **`@extend`** | Method | Registers a function as a dynamic completion extender for caller tables. | `@extend <item?: number> <itemType?: string> <child?: number> <childType?: string>` |

---

## Semantic Indentation & Inheritance

Indentation within Nodeal block comments is **semantic**. Decorators indented beneath other decorators become their "children", inheriting their parent's execution context.

### Example: Environment-Scoped Behaviors
In the snippet below, the `@hidden` and `@deprecated` tags are scoped exclusively to the **Client**. On the Server, the method remains fully visible and active:

```luau
local __=_G() local MatchmakingService = {}

--[=[
    Synchronizes match state with all connected peers.
    
    @client
        @hidden
        @deprecated
    @server
        @priority 10
]=]
function MatchmakingService:SyncState(): ()
    -- ...
end

return __(MatchmakingService)
```

---

## Module-Level (Header) Decorators

Module-level decorators are placed at the very top of a script, preceding the `local __=_G()` statement. The Pre-Parser compiles these into the `ContentHeader` attribute:

```luau
--[=[
    @priority 10
    @server true
]=]
local __=_G() local DatabaseBootstrapper = {}

-- Module logic...

return __(DatabaseBootstrapper)
```

* **`@priority <priority: number>`**: Defines where this module sits in the startup execution queue. Modules with lower numbers load first (default is `255`).
* **`@server true` / `@client true`**: Dictates execution context. If a module has `@server true`, it is completely excluded from client replication and loading.

---

## Method-Level Decorators

Method-level decorators are placed directly above a function declaration:

### `@build` and `@init`
Control the framework lifecycle execution:
```luau
local __=_G() local DataService = {}

--[=[
    @build
]=]
function DataService.SetupCache(): ()
    -- Executes immediately during module loading (Build phase)
end

--[=[
    @init
]=]
function DataService.StartListeners(): ()
    -- Executes during framework ignition once all other services are loaded
end

--[=[
    @init false
]=]
function DataService.Init(): ()
    -- Explicitly DISABLED: will NOT run during framework ignition
end

return __(DataService)
```

### `@extend`
Registers a function as a dynamic completion extender. Calls to this function dynamically add new typed members to the caller table in Studio autocompletion:
```luau
--[=[
    @extend 1 "Entity" 2 "Component"
]=]
function EntityManager:AddComponent(entityInstance: any, componentName: string)
    -- In Studio, calling EntityManager:AddComponent(player, "Health")
    -- dynamically exposes Health component members on the player table!
end
```

---

## Authoring Custom Decorators

Nodeal allows you to create your own domain-specific decorators using <code class="language-lua">game:RegisterDecorator()</code>:

```luau
local __=_G() local PermissionsPlugin = {}

-- Register the "@permission <level: string>" decorator
game:RegisterDecorator("permission", function(context, targetFunc, requiredRole: string)
    return function(self, player: Player, ...)
        local userRole = player:GetAttribute("Role") or "Guest"
        if userRole == requiredRole or userRole == "Admin" then
            return targetFunc(self, player, ...)
        else
            warn(`Permission denied: {player.Name} lacks role '{requiredRole}'`)
        end
    end
end)

return __(PermissionsPlugin)
```

### Advanced Collectors with `@collect` and `@export`
When building framework plugins (such as an automated networking layer or command dispatcher), use `@collect` and `@export`:

```luau
--[=[
    @collect
    @export documentation arguments returns
]=]
game:RegisterDecorator("command", function(context, func, commandName: string?)
    return func
end)
```

When this decorator is used anywhere in your project:
```luau
--[=[
    @command "kick"
]=]
function AdminCommands:KickPlayer(player: Player, target: Player, reason: string): ()
    target:Kick(reason)
end
```

The defining module can query all registered commands at runtime via [`Node:GetCollected()`](../references/node):
```luau
local commands = script:GetCollected("command")
for _, item in commands do
    print(`Registered command '{item.args[1]}' from module '{item.modules[1]}'`)
    local targetModule = item:Resolve()
end
```
