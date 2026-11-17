---
title: "Services"
description: "Master Nodeal Services: register custom singletons, discover dependencies with game:GetService, and wrap native Roblox engine services."
category: "Modules"
order: 6
---

Services are singleton objects that manage specific domains of gameplay logic or persistent state (e.g. `DataService`, `InventoryService`, `CombatService`).

Nodeal introduces a unified architecture that merges Roblox's native C++ engine services with your custom Luau services under a single, seamless **`game:GetService()`** API.

---

## Defining & Registering a Service

To define a custom service, create a module that registers itself with the framework using <code class="language-lua">game:RegisterService()</code>:

```luau
local __=_G() local InventoryService = {}

--// State //--
local playerInventories = {}

--// Lifecycle Hooks //--
function InventoryService.Build(): ()
    -- Executes immediately upon module loading
end

function InventoryService.Init(): ()
    -- Executes during framework ignition once all services are ready
    print("InventoryService initialized.")
end

--// Public Methods //--
function InventoryService:AddItem(player: Player, itemId: string, amount: number): boolean
    local inventory = playerInventories[player] or {}
    inventory[itemId] = (inventory[itemId] or 0) + (amount or 1)
    playerInventories[player] = inventory
    return true
end

function InventoryService:GetItems(player: Player): { [string]: number }
    return playerInventories[player] or {}
end

-- Register under the name "InventoryService"
game:RegisterService("InventoryService", InventoryService)

return __(InventoryService)
```

> [!NOTE]
> Custom services are instantiated during the module loading phase. Any service functions decorated with `@build` or named `Build` execute immediately during registration. Any functions decorated with `@init` or named `Init` execute after all modules have completed their Build phase.

---

## Service Discovery

To retrieve services in your modules, use standard Roblox syntax:

```luau
local __=_G() local PlayerController = {}

-- 1. Resolves a custom Nodeal service
local InventoryService = game:GetService("InventoryService")

-- 2. Falls back seamlessly to the native Roblox engine
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

return __(PlayerController)
```

### Discovery Pipeline
When `game:GetService("ServiceName")` is invoked:
1. **Custom Service Lookup**: Nodeal inspects `service_registry`. If a custom service has been registered under that name, it is returned immediately.
2. **Native Engine Fallback**: If no custom service matches, it queries Roblox's native C++ engine (returning services like `HttpService`, `RunService`, etc.).
3. **Lazy Proxy Fallback**: If a custom service has not yet finished registering, Nodeal returns a lazy proxy that waits for the service to become available, throwing a descriptive error if accessed prematurely.

### Verifying Service Existence
You can verify if a service exists (custom or native) using `game:HasService()`:

```luau
if game:HasService("AnalyticsService") then
    local Analytics = game:GetService("AnalyticsService")
    Analytics:SendMetric("SessionStart")
end
```

---

## Context & Security Boundaries

To maintain strict client-server separation and prevent exploiters from accessing backend logic, Nodeal enforces context boundaries on services:

| Context | Typical Systems | Scoping Rule |
| :--- | :--- | :--- |
| **Server Context** | `DataStoreService`, `AntiCheatService`, `MatchmakingService` | ❌ **Completely inaccessible to the client.** Excluded from network replication. |
| **Client Context** | `CameraController`, `UIController`, `SoundManager` | ❌ **Inaccessible to the server.** Runs strictly on the local machine. |
| **Shared Context** | `NetworkRouter`, `ConfigService`, `ItemCatalog` | Accessible and shared between both Server and Client environments. |

* **Server-Only Services**: Services placed in `ServerStorage` or `ServerScriptService` (or tagged with the `@server true` header decorator) are completely excluded from client replication.
* **Client-Only Services**: Services placed in `StarterPlayerScripts` (or tagged with `@client true`) are never loaded or executed on the server.
* **Shared Services**: Services placed in `ReplicatedStorage` are accessible in both execution contexts.

> [!CAUTION]
> If a client script attempts to retrieve a server-only service via `game:GetService()`, Nodeal returns `nil` and outputs an access violation warning in the Roblox Studio developer console.

---

## Wrapping Native Engine Services

Nodeal allows you to transparently wrap and extend standard Roblox engine services using the enhanced `newproxy()` global. This allows you to add helper methods across your entire codebase without modifying external libraries.

### Example: Extending `TweenService`
Here, we create a proxy that forwards standard calls to Roblox's native `TweenService`, while adding a custom `:Pulse()` utility method:

```luau
local __=_G()
local NativeTweenService = game:GetService("TweenService")

-- Wrap the native engine service in a virtual proxy object
local BetterTweenService = newproxy(NativeTweenService)

-- Add a custom helper method to the proxy
function BetterTweenService:Pulse(targetInstance: GuiObject, duration: number?): Tween
    local tweenInfo = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
    local tween = NativeTweenService:Create(targetInstance, tweenInfo, {
        Size = targetInstance.Size + UDim2.fromScale(0.1, 0.1)
    })
    tween:Play()
    return tween
end

-- Register as "TweenService" to override the native engine service project-wide
game:RegisterService("TweenService", BetterTweenService)

return __(BetterTweenService)
```

In any other module script, calling `game:GetService("TweenService")` now resolves to your enhanced `BetterTweenService` proxy. All native methods (`:Create()`, `:GetValue()`) continue to work seamlessly, with the added availability of `:Pulse()`.