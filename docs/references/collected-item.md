---
title: "CollectedItem"
description: "API Reference for the CollectedItem class, representing metadata and invocation records captured via the @collect decorator pipeline."
category: "API Reference"
order: 5
---

The **`CollectedItem`** class is a specialized metatable record returned by [`Node:GetCollected()`](./node).

When a decorator is declared with the `@collect` directive in Roblox Studio, Nodeal's background Pre-Parser automatically indexes every method across the entire codebase annotated with that decorator. These collected records are compiled into the defining module's payload and made accessible at runtime as `CollectedItem` instances.

---

## Properties

| Property | Type | Description |
| :--- | :--- | :--- |
| **`modules`** | `{ string }` | An array of module names that define this decorated method. |
| **`services`** | `{ string }` | An array of custom service names that define this decorated method. |
| **`method`** | `string` | The string identifier of the decorated method (e.g. `"OnPlayerDamaged"`). |
| **`access`** | `string` | The call operator used to define the method: `":"` (method with self) or `"."` (static function). |
| **`exports`** | `{ [string]: any }` | Extracted metadata defined via `@export` tags (such as argument schemas or return types). |
| **`args`** | `{ any }` | An array containing any arguments passed to the decorator tag in the block comment. |
| **`raw`** | `table` | The raw tuple data table stored in the payload. |

---

## Methods Summary

| Method | Parameters | Return Type | Description |
| :--- | :--- | :--- | :--- |
| **`Resolve`** | `targetName?: string` | `any?` | Dynamically resolves the target service or module table from the runtime registry. |
| **`GetUsage`** | `stackLevel?: number, targetName?: string` | `boolean?` | Checks whether this decorated method has been invoked based on static call analysis. |

---

## Detailed Methods

<Method name="Resolve" parameters="targetName?: string" returns="any?" scope="Shared">
  Resolves and returns the actual runtime instance or singleton table that owns this decorated method.

  If the defining script was registered as a service, it resolves via `game:GetService()`. If registered as a module, it resolves via `game:GetModule()`.

  ### Parameters
  * `targetName`: Optional string. If multiple services or modules share the record, specifies which one to resolve. Defaults to the primary service or module.

  ### Returns
  * `any?`: The resolved module or service table.

  ### Example
  ```luau
  local __=_G() local NetworkRouter = {}

  local netEndpoints = script:GetCollected("net")
  for _, item in netEndpoints do
      local service = item:Resolve()
      local methodFunc = service[item.method]

      print(`Binding network listener to {item.method} on service {item.services[1]}`)
  end

  return __(NetworkRouter)
  ```
</Method>

<Method name="GetUsage" parameters="stackLevel?: number, targetName?: string" returns="boolean?" scope="Shared">
  Queries Nodeal's static call analysis registry (`calls_registry`) to determine if the decorated method has active callers anywhere in the codebase.

  ### Parameters
  * `stackLevel`: Optional stack level depth for caller resolution.
  * `targetName`: Optional target name override.

  ### Returns
  * `boolean?`: `true` if calls to this method were detected by the Pre-Parser; otherwise `false` or `nil`.
</Method>

---

## Practical Example: Building an Automated Network Router

Here is how `@collect` and `CollectedItem` work together to build a zero-boilerplate networking system:

### Registering the Decorator with `@collect`
In your network manager module:
```luau
--[=[
    @collect
    @export documentation arguments
]=]
game:RegisterDecorator("net", function(context, func, remoteName: string?)
    return func -- Keep untouched at runtime, collected by Pre-Parser
end)
```

### Annotating Methods Across Your Project
In any service:
```luau
local __=_G() local CombatService = {}

--[=[
    @net "AttackRequest"
]=]
function CombatService:ProcessAttack(player: Player, weaponId: string)
    print(`Processing attack from {player.Name}`)
end

game:RegisterService("CombatService", CombatService)
return __(CombatService)
```

### Routing Calls Automatically at Runtime
In your network bootstrapper:
```luau
local __=_G() local NetworkDispatcher = {}

function NetworkDispatcher.Init()
    local endpoints = script:GetCollected("net")
    for _, item in endpoints do
        local remoteName = item.args[1] or item.method
        local service = item:Resolve()

        -- Automatically wire up Roblox RemoteEvents!
        local remote = Instance.new("RemoteEvent")
        remote.Name = remoteName
        remote.Parent = game.ReplicatedStorage

        remote.OnServerEvent:Connect(function(player, ...)
            service[item.method](service, player, ...)
        end)
    end
end

return __(NetworkDispatcher)
```
