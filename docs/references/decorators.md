---
title: "Decorators"
description: "Technical reference for all 17 built-in comment-based decorators in Nodeal: syntax, parameters, targets, and compiler behaviors."
category: "API Reference"
order: 4
---

The **Decorators Reference** provides technical specifications for all 17 built-in comment-based decorators recognized by Nodeal's background Pre-Parser and runtime engine.

Decorators are declared inside standard Luau block comments (`--[=[ ... ]=]`) directly above module or function definitions.

---

## Decorators Summary

| Decorator | Target | Default | Primary Purpose |
| :--- | :--- | :--- | :--- |
| **`@server`** | Method / Module | `true` | Restricts execution to the Server; excludes from client network replication. |
| **`@client`** | Method / Module | `true` | Restricts execution to the Client; excludes from server execution. |
| **`@context`** | Registration | `*` | Defines context visibility for IntelliSense autocompletion (`*`, `client`, `server`). |
| **`@hidden`** | Method | `true` | Hides a method from Studio autocompletion while keeping it callable. |
| **`@build`** | Method | `true` | Schedules immediate execution during the module loading phase. |
| **`@init`** | Method | `true` | Schedules execution during the Ignition phase (after all modules have built). |
| **`@priority`** | Module Header | `math.huge` | Sets execution order priority (lower numbers load first). |
| **`@param`** | Method | Required | Documents parameter names and descriptions in Studio hover tooltips. |
| **`@return`** | Method | Optional | Documents return values and types in Studio hover tooltips. |
| **`@see`** | Method | Required | Embeds an external documentation URL into the hover tooltip. |
| **`@example`** | Method | Required | Embeds a syntax-highlighted code sample into the hover tooltip. |
| **`@alias`** | Method | Required | Registers alternative names for a method in Studio autocomplete. |
| **`@deprecated`** | Method | `true` | Applies visual strikethrough in autocomplete popups to discourage use. |
| **`@overloads`** | Method | Required | Informs the Studio type solver of multiple overloaded call signatures. |
| **`@collect`** | Registration | None | Instructs the Pre-Parser to aggregate all decorated methods into `Node:GetCollected()`. |
| **`@export`** | Registration | None | Extracts method metadata (`arguments`, `returns`, `usages`) for runtime reflection. |
| **`@extend`** | Method | None | Dynamically injects typed autocomplete members into caller tables in Studio. |

---

## Execution & Context Decorators

<Method name="@server" parameters="active?: boolean | ...decorator" returns="void" scope="Shared">
  Restricts the annotated function or module to the **Server** context.
  
  * **Module Target**: When placed in the module docblock header, the client runtime completely ignores and never loads the module.
  * **Method Target**: Wraps the method with a runtime guard that throws or warns if called on the client.
  * **Indented Scoping**: Can be placed above nested decorators to apply them exclusively on the server.

  ### Example
  ```luau
  --[=[
      @server true
  ]=]
  function DataService:SaveProfile(player: Player): ()
      -- Only executable on the server
  end
  ```
</Method>

<Method name="@client" parameters="active?: boolean | ...decorator" returns="void" scope="Shared">
  Restricts the annotated function or module to the **Client** context.

  * **Module Target**: When placed in the module docblock header, the server runtime completely ignores the module.
  * **Method Target**: Restricts execution to client controllers.

  ### Example
  ```luau
  --[=[
      @client
  ]=]
  function CameraController:Shake(intensity: number): ()
      -- Only executable on the client
  end
  ```
</Method>

<Method name="@context" parameters="...contexts: string" returns="void" scope="Shared">
  Specifies execution contexts for autocomplete and IntelliSense filtering. Supported values include `*` (universal), `client`, and `server`.

  ### Example
  ```luau
  --[=[
      @context client server
  ]=]
  ```
</Method>

<Method name="@hidden" parameters="hidden?: boolean" returns="void" scope="Shared">
  Hides the decorated function from Roblox Studio's autocompletion dropdown while keeping it accessible at runtime. Useful for internal OOP utilities or private methods.

  ### Example
  ```luau
  --[=[
      @hidden
  ]=]
  function MyClass:_internalHelper(): ()
      -- Hidden from autocomplete suggestions
  end
  ```
</Method>

---

## Lifecycle & Priority Decorators

<Method name="@build" parameters="active?: boolean" returns="void" scope="Shared">
  Configures immediate constructor execution during the module loading phase (Phase 5).
  
  * By default, functions named `Build` execute automatically.
  * `@build true` forces any custom-named function to run during the Build phase.
  * `@build false` disables automatic execution on functions named `Build`.

  ### Example
  ```luau
  --[=[
      @build
  ]=]
  function PlayerService.SetupCache(): ()
      PlayerService.Cache = {}
  end
  ```
</Method>

<Method name="@init" parameters="active?: boolean" returns="void" scope="Shared">
  Configures execution during the framework Ignition phase (Phase 6), guaranteed to run only after **every module** in the project has finished its Build phase.

  * By default, functions named `Init` execute automatically during Ignition.
  * `@init true` forces any custom-named function to run during Ignition.
  * `@init false` disables automatic execution on functions named `Init`.

  ### Example
  ```luau
  --[=[
      @init
  ]=]
  function MatchService.StartGameLoop(): ()
      task.spawn(function()
          -- Cross-service communication is 100% safe here
      end)
  end
  ```
</Method>

<Method name="@priority" parameters="priority: number" returns="void" scope="Shared">
  Header decorator defining the module's load order priority. Lower numbers are required and built earlier in the startup sequence.

  ### Example
  ```luau
  --[=[
      @priority 1
  ]=]
  local __=_G() local CoreDatabaseService = {}
  -- ...
  return __(CoreDatabaseService)
  ```
</Method>

---

## Documentation & IntelliSense Decorators

<Method name="@param" parameters="name: string, description?: string" returns="void" scope="Shared">
  Documents a method parameter. The Studio Pre-Parser reads this tag to populate parameter names, types, and descriptions in the script editor hover tooltip.

  ### Example
  ```luau
  --[=[
      @param targetPlayer The player receiving the reward.
      @param goldAmount The amount of currency to add.
  ]=]
  function EconomyService:Reward(targetPlayer: Player, goldAmount: number): () end
  ```
</Method>

<Method name="@return" parameters="description?: string" returns="void" scope="Shared">
  Documents the return value of a method in Studio hover tooltips.

  ### Example
  ```luau
  --[=[
      @return True if the purchase was authorized; otherwise false.
  ]=]
  function ShopService:ProcessOrder(orderId: string): boolean end
  ```
</Method>

<Method name="@see" parameters="url: string" returns="void" scope="Shared">
  Embeds an external documentation URL into the method hover tooltip in Studio.

  ### Example
  ```luau
  --[=[
      @see https://www.nodeal.dev/docs/services
  ]=]
  function MyService:Action() end
  ```
</Method>

<Method name="@example" parameters="code: string" returns="void" scope="Shared">
  Embeds a syntax-highlighted Luau code example directly into the hover tooltip.

  ### Example
  ```luau
  --[=[
      @example
          local profile = PlayerService:GetProfile(player)
          print(profile.Gold)
  ]=]
  function PlayerService:GetProfile(player: Player): Profile end
  ```
</Method>

<Method name="@alias" parameters="...aliases: string" returns="void" scope="Shared">
  Registers alternative alias names for a method in the Studio autocompletion dropdown. Selecting an alias inserts the underlying method call.

  ### Example
  ```luau
  --[=[
      @alias Delete Remove
  ]=]
  function Entity:Destroy(): () end
  ```
</Method>

<Method name="@deprecated" parameters="deprecated?: boolean" returns="void" scope="Shared">
  Flags a method as deprecated. Studio's autocomplete applies a visual strikethrough to the method label in dropdowns.

  ### Example
  ```luau
  --[=[
      @deprecated true
  ]=]
  function OldService:LegacyMethod(): () end
  ```
</Method>

<Method name="@overloads" parameters="count: number" returns="void" scope="Shared">
  Specifies the number of alternate function signatures available for type solvers and reflection tools.

  ### Example
  ```luau
  --[=[
      @overloads 2
  ]=]
  function Utility:Format(value: any, options: any?): string end
  ```
</Method>

---

## Metaprogramming & Collector Decorators

<Method name="@collect" parameters="" returns="void" scope="Shared">
  Placed above a custom decorator registration to mark it as a **collector**. The background Pre-Parser will index all methods across the entire codebase tagged with this decorator into `ContentPayload[".collected"]`.
  
  At runtime, defining scripts retrieve these records via [`Node:GetCollected()`](./node) as [`CollectedItem`](./collected-item) objects.

  ### Example
  ```luau
  --[=[
      @collect
  ]=]
  game:RegisterDecorator("command", function(ctx: DecoratorContext)
      return ctx.WrappedFunction
  end)
  ```
</Method>

<Method name="@export" parameters="...exports: string" returns="void" scope="Shared">
  Directs the Pre-Parser to extract advanced AST metadata from decorated methods for reflection. Supported extractors include:
  * `arguments`: Extracts parameter names and inferred types.
  * `returns`: Extracts return types.
  * `usages`: Extracts static call site lines.

  ### Example
  ```luau
  --[=[
      @collect
      @export arguments returns
  ]=]
  game:RegisterDecorator("route", function(ctx: DecoratorContext)
      return ctx.WrappedFunction
  end)
  ```
</Method>

<Method name="@extend" parameters="itemIndex?: number, itemType?: string, childIndex?: number, childType?: string" returns="void" scope="Shared">
  Registers a function as a dynamic completion extender. When a caller invokes this function in the script editor, the Studio plugin dynamically expands the caller's autocompletion suggestions with new typed fields.
</Method>
