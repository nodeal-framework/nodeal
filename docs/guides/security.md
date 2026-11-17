---
title: "Security"
description: "Learn how Nodeal protects game logic through memory shielding, client instance cleaning, production log privacy, and context boundaries."
category: "Architecture"
order: 10
---

Nodeal includes built-in security features designed to protect your game logic and sensitive data without requiring external obfuscation tools or complicated setup.

---

## Security Overview

| Protection Layer | How It Works | Developer Benefit |
| :--- | :--- | :--- |
| **Passive Memory Shielding** | Calling Roblox's native `require()` on modules returns `nil`. | Prevents client-side scripts and executors from inspecting module tables. |
| **Hierarchy Cleaning** | Detaches and cleans physical `ModuleScript` instances on the client. | Prevents tools from scanning and locating scripts in the game hierarchy. |
| **Production Privacy** | Configurable flags (`PrivatePrint`, `PrivateWarn`, `PrivateError`) in the Manifest. | Suppresses logs and stack traces in live production servers. |
| **Tamper Detection** | Detects unauthorized runtime modifications or lifecycle interference. | Alerts developers in Studio and desynchronizes compromised client connections. |
| **Context Boundaries** | Scoping rules (`@server`, `@client`, ServerStorage separation). | Server code is never sent across the network to client machines. |

---

## Passive Memory Shielding

In standard Roblox development, any client script or executor can call `require()` on any replicated `ModuleScript` to inspect its exported table and state:

```luau
-- Traditional Roblox (Vulnerable):
local ExploiterData = require(game.ReplicatedStorage.Modules.PlayerData)
-- The caller now has access to PlayerData's exported functions and state!
```

### The Nodeal Approach
In Nodeal, every module completes its handshake using `return __(module)`:

```luau
local __=_G() local PlayerData = {}

-- ... module logic ...

return __(PlayerData)
```

Nodeal registers the module securely in its internal service registry and returns `nil` to Roblox's native `require` engine.

If any external script attempts to `require()` the physical script instance directly, it simply receives `nil`:

```luau
local result = require(game.ReplicatedStorage.Source.PlayerData)
print(result) -- nil
```

Inside your framework code, modules continue to resolve cleanly through Nodeal's APIs:
```luau
local PlayerData = game:GetModule("PlayerData")
```

---

## Client Instance Cleaning

Once client modules are loaded into memory, Nodeal automatically cleans up their physical instances from the client's DataModel:

* **Invisible in Hierarchy Scanners**: Tools that scan `game:GetDescendants()` cannot find your scripts because they no longer live in the explorer tree.
* **In-Memory Execution**: Your code runs safely in protected Luau closures in RAM, decoupled from physical instances.
* **Clean Memory Footprint**: Removes unnecessary script objects and attributes once initialization is complete.

---

## Production Log Privacy

Roblox games often leak sensitive information—such as database IDs, internal URLs, or security check details—through unscrubbed `print()` and `warn()` statements.

Nodeal includes privacy controls configured on the runtime **`Manifest`**:

| Setting | Type | Default | Behavior in Production |
| :--- | :--- | :--- | :--- |
| **`PrivatePrint`** | `boolean` | `true` | Suppresses `print()` messages so they never show in player consoles. |
| **`PrivateWarn`** | `boolean` | `true` | Suppresses `warn()` diagnostics in live servers. |
| **`PrivateError`** | `boolean` | `true` | Yields the calling thread instead of printing stack traces. |
| **`OptimizeProduction`** | `boolean` | `true` | Disables debug callsite traces and shortens internal identifier strings for speed. |

### Why Yield on Error?
When `PrivateError` is active in production, failed assertions and errors freeze the suspect thread rather than throwing an engine error. This gives exploiters no stack traces to read, while keeping the rest of your server running smoothly.

---

## Active Tamper Detection

Nodeal continuously monitors framework integrity:

* **Unauthorized Handshakes**: Ensures `_G()` is only called by authorized modules within tagged root containers.
* **Lifecycle State Protection**: Watches for external attempts to manipulate or fake framework completion flags.
* **Runtime Relocation**: Detects if core framework scripts are unexpectedly reparented.

### Behavior
* **In Studio**: Throws an immediate, descriptive error in the Output window to help you debug configuration mistakes.
* **In Live Games**: Signals your networking layer to desynchronize the tampered client, preventing unauthorized remote requests from reaching the server.

---

## Context Isolation

To keep your backend secure:

1. **Keep Server Logic in Server Storage**: Store server singletons in `ServerStorage` or `ServerScriptService`.
2. **Use the `@server` Decorator**: If a module lives in a shared folder for project organization, mark it with `@server true` so the client runtime never loads it:
   ```luau
   --[=[
       @server true
   ]=]
   local __=_G() local SecretRewardService = {}

   return __(SecretRewardService)
   ```
3. **Never Trust Client Data**: Always validate parameters on the server before acting on player requests.
