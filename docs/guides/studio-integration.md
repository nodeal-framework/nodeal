---
title: "Studio Integration"
description: "Comprehensive guide to the Nodeal Studio Plugin: Custom Explorer, AST Pre-Parser, dynamic IntelliSense, productivity snippets, and debugging widgets."
category: "Getting Started"
order: 4
---

Nodeal is engineered as a unified, studio-native development environment. The **Nodeal Studio Plugin** serves as both your IDE bridge and a background compiler, connecting Roblox Studio's code editor with the framework's runtime virtualization layer.

---

## Custom Explorer

The **Custom Explorer** replaces the generic Roblox Studio hierarchy view with an architecture-aware workspace tailored for modular game development:

| Context Container | Scoping | Example Systems | Role Badge |
| :--- | :--- | :--- | :--- |
| **`ReplicatedStorage/Shared`** | `[Shared]` | `MathEx`, `NetworkRouter` | Built-in Global / Service |
| **`ServerStorage/Server`** | `[Server]` | `PlayerData`, `AntiCheatService` | Service |
| **`ReplicatedStorage/Client`** | `[Client]` | `UIController`, `CameraManager` | Service / Module |

### Key Explorer Features
* **Architectural Role Categorization**: Scripts are automatically Badged and colored depending on whether they operate as **Services** (singletons), **Built-ins** (globals), or standard **Modules** (libraries/OOP classes).
* **Context Filtering**: Instantly highlights whether a module script executes on the **Server**, **Client**, or in **Shared** memory.
* **Instant Script Creation**: Press <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>M</kbd> or right-click any folder to insert a pre-configured script from one of the built-in templates.

### Built-in Explorer Templates

| Template | File Structure | Intended Use Case |
| :--- | :--- | :--- |
| **`Singleton`** | Includes `.Init()` lifecycle hook and service registration boilerplate. | Stateful domain managers, services, and controllers. |
| **`Object`** | OOP class template featuring `.__index`, `.new()`, and `:Destroy()`. | Entities, weapons, UI components, data structures. |
| **`Library`** | Clean functional module template for stateless utilities. | Math extensions, algorithms, string formatters. |

---

## IntelliSense & Type Inference

Standard Roblox Studio autocomplete cannot natively resolve dynamic dependencies or virtualized globals. Nodeal bridges this gap with a custom **TypeParser** and **TypeResolver** running natively in the plugin.

### Interactive Tooltips & Metadata
When you document functions using Luau block comments, the plugin generates rich, formatted tooltip popups in Studio's script editor:

```luau
--[=[
    Fires a spell projectile towards a world position.

    @param targetPosition World destination for projectile trajectory.
    @param projectileSpeed Velocity in studs per second.
    @return The spawned projectile model instance.
    @see https://www.nodeal.dev/docs
    @example
        local spell = SpellService:CastSpell(targetPos, 120)
]=]
function SpellService:CastSpell(targetPosition: Vector3, projectileSpeed: number): Model
    -- ...
end
```

### Autocomplete Features Provided by Nodeal
* **Parameter & Return Documentation**: Parses `@param` and `@return` annotations directly into the hover tooltip.
* **Syntax-Highlighted Examples**: Code blocks tagged with `@example` are formatted with full syntax highlighting.
* **Deprecation Badges**: Marking a function with `@deprecated` applies a visual strikethrough in autocomplete dropdowns to warn team members.
* **Dynamic Autocomplete Extensions (`@extend`)**: Functions decorated with `@extend` dynamically add new typed members and child tables to the caller's autocompletion popup as you write code.

---

## Productivity Snippets & Shortcuts

The Nodeal Studio Plugin registers smart autocompletion snippets that streamline repetitive import statements:

### The `!` Docblock Snippet
Typing `!` in the script editor triggers the documentation block snippet, expanding instantly into:
```luau
--[=[
    
]=]
```

### The `$` Module Import Snippet
Typing `$` followed by the name of any registered module (e.g. `$PlayerData`) generates the full location-agnostic import statement:
```luau
local PlayerData = game:GetModule("PlayerData")
```

### The `:` Service Import Snippet
Typing `:` followed by the name of any custom service or native Roblox service (e.g. `:InventoryService` or `:TweenService`) generates the unified service lookup:
```luau
local InventoryService = game:GetService("InventoryService")
```
This snippet draws from both your custom services and Roblox's complete C++ `ApiDump`, saving thousands of keystrokes during active development.