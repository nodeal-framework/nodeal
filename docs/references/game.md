---
title: "Game"
description: "Comprehensive documentation for all methods and extensions injected into the Roblox DataModel (game) proxy by Nodeal."
category: "API Reference"
order: 2
---

The Nodeal virtualization layer wraps Roblox's native `DataModel` (the `game` global) inside a high-performance proxy object. This proxy transparently intercepts standard engine lookups, forwards native calls to the C++ engine, and injects framework APIs for **location-agnostic module resolution**, **custom service registration**, and **built-in library injection**.

---

## Methods Summary

| Method | Parameters | Return Type | Description |
| :--- | :--- | :--- | :--- |
| **`GetModule`** | `moduleName: string` | `Node \| any` | Resolves a registered module by its string name, abstracting physical folder locations. |
| **`HasModule`** | `moduleName: string, loaded?: boolean` | `boolean` | Checks if a module is registered in the name registry, and optionally if it has finished loading. |
| **`GetService`** | `serviceName: string` | `any` | Intercepts service retrieval: checks custom singletons first before native engine services. |
| **`HasService`** | `serviceName: string` | `boolean` | Checks if a service is registered as a custom singleton or exists as a native Roblox service. |
| **`RegisterService`**| `serviceName: string, instance?: table \| Userdata` | `void` | Registers a singleton service discoverable project-wide via `game:GetService()`. |
| **`RegisterModule`** | `moduleName: string, instance?: table \| Userdata` | `void` | Dynamically registers or updates a module in the runtime name lookup registry as a `Node`. |
| **`RegisterBuiltIn`**| `builtInName: string, library: table \| Userdata` | `void` | Injects a stateless library or utility directly into the global namespace of all modules. |
| **`RegisterDecorator`**| `tag: string, wrapper: function` | `void` | Registers a custom comment-based decorator wrapper to modify function behaviors. |
| **`GetNative`** | `name: string` | `any?` | Directly retrieves native Luau/Roblox environment symbols before virtualization. |

---

## Detailed Methods

<Method name="GetModule" parameters="moduleName: string" returns="Node | any" scope="Shared">
  Resolves a module script by its registered name. This method abstracts away physical folder structures, allowing modules to be resolved location-agnostically across `ReplicatedStorage`, `ServerScriptService`, or custom roots.

  ### Lazy Resolution & Error Safety
  If the module has already loaded, `GetModule` instantly returns its cached content table. If the module has not yet executed its handshake, it returns a safe proxy metatable. If code attempts to index or assign fields on a module that is never registered, it throws a verbose error:
  ```
  attempt to index field '...' on module '...' which has not been registered
  ```

  ### Parameters
  * `moduleName`: The unique string name of the registered module.

  ### Returns
  * `Node | any`: The loaded module content table or lazy proxy object.

  ### Example
  ```luau
  local __=_G() local InventoryController = {}

  -- Resolves the PlayerData module regardless of where it is physically placed
  local PlayerData = game:GetModule("PlayerData")
  local profile = PlayerData:GetProfile(game.Players.LocalPlayer)

  return __(InventoryController)
  ```
</Method>

<Method name="HasModule" parameters="moduleName: string, loaded?: boolean" returns="boolean" scope="Shared">
  Checks whether a module exists in Nodeal's runtime name lookup registry (`name_registry`).

  ### Parameters
  * `moduleName`: The string name of the module to verify.
  * `loaded`: Optional boolean. If set to `true`, the method returns `true` only if the module is registered **and** has completed its execution handshake (`node.Content ~= nil`).

  ### Returns
  * `boolean`: `true` if the module exists (and is loaded, if requested); otherwise `false`.

  ### Example
  ```luau
  local __=_G() local Bootstrapper = {}

  if game:HasModule("AnalyticsService", true) then
      local Analytics = game:GetModule("AnalyticsService")
      Analytics:TrackEvent("GameStart")
  else
      print("AnalyticsService is not yet loaded.")
  end

  return __(Bootstrapper)
  ```
</Method>

<Method name="GetService" parameters="serviceName: string" returns="any" scope="Shared">
  Resolves and retrieves a service. This is a drop-in, virtualized override for Roblox's native <code class="language-lua">game:GetService()</code>.

  ### Lookup Pipeline
  1. **Custom Registry Check**: Nodeal checks its internal `service_registry` first. If a custom service was registered via `game:RegisterService()`, it is returned immediately.
  2. **Native Engine Fallback**: If no custom service matches, it calls Roblox's native engine `game:GetService()`, returning standard services like `TweenService`, `RunService`, or `Players`.
  3. **Lazy Proxy Fallback**: If the service has not yet been registered, it returns a proxy that waits for registration and throws an explicit error if accessed prematurely.

  ### Parameters
  * `serviceName`: The class name of the native Roblox service or the registered name of a custom service.

  ### Returns
  * `any`: The requested custom service table or native Roblox service Instance.

  ### Example
  ```luau
  local __=_G() local MatchController = {}

  -- 1. Resolves a custom Nodeal service
  local InventoryService = game:GetService("InventoryService")

  -- 2. Falls back seamlessly to the native Roblox engine
  local TweenService = game:GetService("TweenService")
  local Players = game:GetService("Players")

  return __(MatchController)
  ```
</Method>

<Method name="HasService" parameters="serviceName: string" returns="boolean" scope="Shared">
  Checks whether a service is available to be consumed, querying both the custom service registry and native Roblox engine services.

  ### Parameters
  * `serviceName`: The name of the service to check.

  ### Returns
  * `boolean`: `true` if the service exists either in the custom service registry or as a valid native Roblox service; otherwise `false`.

  ### Example
  ```luau
  local hasCustomShop = game:HasService("ShopService")
  local hasTween = game:HasService("TweenService")

  print(hasCustomShop) -- true (if registered)
  print(hasTween)      -- true (native Roblox service)
  ```
</Method>

<Method name="RegisterService" parameters="serviceName: string, instance?: table | Userdata" returns="void" scope="Shared">
  Registers a singleton object as a "Service". Once registered, this service becomes discoverable context-wide using the virtualized <code class="language-lua">game:GetService()</code> API.

  ### Engine Service Overriding
  If a custom service's name matches a native Roblox engine service (e.g. `"TweenService"` or `"RunService"`), Nodeal's service registry takes precedence. This allows you to wrap, extend, or completely mock native engine services cleanly without breaking existing caller code.

  ### Parameters
  * `serviceName`: The identifier under which the service is registered.
  * `instance`: The table or userdata implementing the service methods. In the Studio Plugin, if omitted, it automatically defaults to the module's name.

  ### Example
  ```luau
  local __=_G() local EconomyService = {}

  function EconomyService:TransferCoins(fromPlayer: Player, toPlayer: Player, amount: number): boolean
      -- Business logic...
      return true
  end

  -- Register as a first-class service
  game:RegisterService("EconomyService", EconomyService)

  return __(EconomyService)
  ```
</Method>

<Method name="RegisterModule" parameters="moduleName: string, instance?: table | Userdata" returns="void" scope="Shared">
  Dynamically registers or updates a module in Nodeal's runtime name lookup registry (`name_registry`) as a virtual <code class="language-lua">Node</code>.

  This allows you to programmatically register dynamically generated modules, third-party libraries, or runtime components so they can be retrieved anywhere via `game:GetModule(moduleName)` or `require(moduleName)`.

  ### Parameters
  * `moduleName`: The string name of the module.
  * `instance`: The module's exported content table or instance.

  ### Example
  ```luau
  local __=_G() local ModuleFactory = {}

  local DynamicMath = {
      square = function(n: number) return n * n end
  }

  game:RegisterModule("DynamicMath", DynamicMath)

  -- Now accessible from any script in the project:
  local MathMod = game:GetModule("DynamicMath")
  print(MathMod.square(4)) -- 16

  return __(ModuleFactory)
  ```
</Method>

<Method name="RegisterBuiltIn" parameters="builtInName: string, library: table | Userdata" returns="void" scope="Shared">
  Injects a stateless library or utility directly into the virtualized global namespace of every module script in your project.

  Unlike services (which must be retrieved using `game:GetService()`), Built-ins become **first-class globals** available directly without requiring imports. You can also use this method to safely extend or monkey-patch standard Lua libraries (such as `math` or `os`) without polluting native engine scripts.

  ### Parameters
  * `builtInName`: The global name to bind the library to in the virtual `universe`.
  * `library`: The table of utility functions.

  ### Example
  ```luau
  local __=_G() local GlobalExtensions = {}

  local MathUtilities = {
      clamp01 = function(v: number): number
          return math.clamp(v, 0, 1)
      end,
  }

  game:RegisterBuiltIn("MathUtils", MathUtilities)

  -- In any other module script:
  -- local alpha = MathUtils.clamp01(0.75)

  return __(GlobalExtensions)
  ```
</Method>

<Method name="RegisterDecorator" parameters="tag: string, wrapper: function" returns="void" scope="Shared">
  Registers a custom compile-time and runtime decorator wrapper. This empowers developers to create domain-specific annotations (such as permission gates, rate limiters, or automated network synchronizers) using Luau block comment syntax (`--[=[ @tag ... ]=]`).

  ### Wrapper Callback Signature
  The wrapper function receives:
  1. `context: DecoratorContext`: A context object describing the decorated method, its parent module, AST metadata, and child decorators.
  2. `targetFunction: (...any) -> ...any`: The function being decorated.
  3. `...decoratorArgs: any`: Any variable arguments passed to the decorator annotation in the block comment.

  The wrapper must return a new closure that wraps `targetFunction`, or `nil` to strip the method from the module.

  ### Parameters
  * `tag`: The decorator tag string (e.g. `"adminOnly"`, `"rateLimit"`).
  * `wrapper`: The wrapper closure function `(context, targetFunc, ...args) -> wrappedFunc`.

  ### Example
  ```luau
  local __=_G() local AdminPlugin = {}

  game:RegisterDecorator("adminOnly", function(context, func, fallbackMessage: string?)
      return function(self, player: Player, ...)
          if player:GetAttribute("IsAdmin") then
              return func(self, player, ...)
          else
              warn(fallbackMessage or `Access Denied for {player.Name}`)
          end
      end
  end)

  return __(AdminPlugin)
  ```

  ### Consuming the Custom Decorator
  ```luau
  --[=[
      @adminOnly "Unauthorized access to BanPlayer"
  ]=]
  function ModerationService:BanPlayer(player: Player, targetUser: Player): ()
      -- Only executes if player has IsAdmin attribute
  end
  ```
</Method>

<Method name="GetNative" parameters="name: string" returns="any?" scope="Shared">
  Retrieves a raw symbol from the native Roblox/Luau environment before virtualization occurred.

  This is useful when writing custom engine wrappers or when you need guaranteed access to native engine functions (e.g. native `print`, `typeof`, `require`, or `debug`) without going through Nodeal's proxy layers.

  ### Parameters
  * `name`: The name of the global symbol to read (e.g. `"print"`, `"typeof"`, `"require"`).

  ### Returns
  * `any?`: The raw native symbol from `getfenv()`.

  ### Example
  ```luau
  local __=_G() local NativeDiagnostics = {}

  -- Access the untouched native print from Roblox
  local nativePrint = game:GetNative("print")
  nativePrint("Direct output to Roblox engine, bypassing Nodeal trace formatting.")

  return __(NativeDiagnostics)
  ```
</Method>
