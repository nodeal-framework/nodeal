---
title: "Modules"
description: "Master the atomic execution unit of Nodeal: module roles, boilerplate architecture, Explorer templates, and the virtual Node script identifier."
category: "Modules"
order: 5
---

Modules are the atomic building blocks of the Nodeal architecture. While physically stored as standard Roblox `ModuleScript` instances, the Nodeal runtime virtualizes them into active, isolated execution units featuring **Dependency Injection**, **Lifecycle Hooks**, and **Context Sandboxing**.

---

## Virtualization Boilerplate

To integrate with Nodeal's security boundaries and metadata pre-compiler, every module script must implement the standardized boilerplate pattern:

```luau
-- 1. Initialize the security accessor
local __=_G()

-- 2. Define the module container
local InventoryModule = {}

-- 3. Implement business logic
function InventoryModule:CalculateWeight(itemCount: number, unitWeight: number): number
    return itemCount * unitWeight
end

-- 4. Complete the handshake and return the module
return __(InventoryModule)
```

### Breakdown of the Handshake
* **`local __=_G()`**: Captures the framework's global setup closure. During the `require` phase, this function acts as the security accessor. It validates the script's origin, injects the virtualized `universe` environment (replacing native `typeof`, `unpack`, and `require`), and attaches the [`Node`](../references/node) proxy to `script`.
* **`return __(InventoryModule)`**: Executes the security handshake. This wrapper:
  1. Resolves compile-time decorators declared in Luau block comments.
  2. Binds lifecycle targets (`Build` and `Init`).
  3. Registers the module in the global name registry (`name_registry`).
  4. Returns `nil` to Roblox's native C++ `require` engine to prevent unauthorized memory reflection.

> [!WARNING]
> Returning the table directly without the handshake wrapper (e.g. `return InventoryModule`) causes a runtime initialization fault and triggers a compilation diagnostic in the Studio Pre-Parser.

---

## Architectural Roles

Nodeal organizes codebase logic into three distinct architectural roles:

| Role | Access Scope | Intended Use Case | Discovery Method |
| :--- | :--- | :--- | :--- |
| **Services** | Global Singleton | Stateful domain singletons (e.g. `DataService`, `CombatService`). | `game:GetService("Name")` |
| **Built-ins** | Framework Global | Stateless global utilities and standard library extensions (e.g. `MathUtils`, `Promise`). | Injected directly into the global environment |
| **Modules** | Reusable Instance / Class | Object-oriented classes, data models, components, and helper libraries. | `game:GetModule("Name")` or `require("Name")` |

---

## Module Creation & Templates

To ensure proper metadata tagging, always create framework scripts using the **Nodeal Custom Explorer** in Roblox Studio:
1. Press <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd> or right-click any folder in the Nodeal Explorer widget.
2. Select your desired archetype: **Singleton**, **Object**, or **Library**.

### Template 1: Singleton (Service)
Used for managers, controllers, and services with lifecycle hooks:
```luau
local __=_G() local MatchService = {}

--// Services //--
local Players = game:GetService("Players")

--// Private State //--
local isMatchActive = false

--// Lifecycle Hooks //--
function MatchService.Build(): ()
    -- Immediate setup during module load
end

function MatchService.Init(): ()
    -- Global initialization once all services are ready
    print("MatchService initialized successfully.")
end

--// Public API //--
function MatchService.StartMatch(): ()
    isMatchActive = true
end

return __(MatchService)
```

### Template 2: Object (OOP Class)
Used for instantiable entities, components, or data structures:
```luau
local __=_G() local CharacterEntity = {}
CharacterEntity.__index = CharacterEntity

export type CharacterEntity = {
    Model: Model,
    Health: number,
    TakeDamage: (self: CharacterEntity, amount: number) -> (),
    Destroy: (self: CharacterEntity) -> (),
}

function CharacterEntity.new(characterModel: Model): CharacterEntity
    local self = setmetatable({}, CharacterEntity)
    self.Model = characterModel
    self.Health = 100
    return self
end

function CharacterEntity:TakeDamage(amount: number): ()
    self.Health = math.max(0, self.Health - amount)
end

function CharacterEntity:Destroy(): ()
    setmetatable(self, nil)
end

return __(CharacterEntity)
```

### Template 3: Library (Stateless Utilities)
Used for pure utility functions, math calculations, and algorithms:
```luau
local __=_G() local MathLibrary = {}

function MathLibrary.Lerp(startValue: number, goalValue: number, alpha: number): number
    return startValue + (goalValue - startValue) * alpha
end

function MathLibrary.Clamp01(value: number): number
    return math.clamp(value, 0, 1)
end

return __(MathLibrary)
```

---

## The Virtual `script` Identifier

Inside any Nodeal module, the global `script` variable is automatically wrapped into a **[`Node`](../references/node)** object.

You can interact with `script` just like a standard Roblox instance, with the addition of framework-specific reflection tools:

```luau
local __=_G() local ExampleModule = {}

-- Inspect hierarchical metadata
print(script.Name)         -- "ExampleModule"
print(script.FullName)     -- "ReplicatedStorage.Source.ExampleModule"

-- Query collected decorator endpoints
local listeners = script:GetCollected("net")
print(`Total network listeners: {#listeners}`)

return __(ExampleModule)
```

---

## Dynamic Module Registration

In addition to static scripts placed in the workspace, you can dynamically register or update modules at runtime using <code class="language-lua">game:RegisterModule()</code>:

```luau
local __=_G() local DynamicLoader = {}

local GeneratedUtility = {
    CalculateFactorial = function(n: number): number
        local result = 1
        for i = 2, n do result *= i end
        return result
    end
}

-- Register module dynamically into the runtime lookup table
game:RegisterModule("GeneratedUtility", GeneratedUtility)

-- Accessible from any other module in your game:
local Util = game:GetModule("GeneratedUtility")
print(Util.CalculateFactorial(5)) -- 120

return __(DynamicLoader)
```
