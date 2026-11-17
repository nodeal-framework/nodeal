---
title: "DecoratorContext"
description: "API Reference for the DecoratorContext class, providing AST reflection and runtime metadata to custom decorator wrappers."
category: "API Reference"
order: 4
---

The **`DecoratorContext`** class encapsulates the compile-time and runtime metadata passed to custom decorator wrapper closures registered with <code class="language-lua">game:RegisterDecorator()</code>.

Whenever a function in your codebase is annotated with a comment-based decorator (e.g. `--[=[ @myDecorator ... ]=]`), Nodeal constructs a `DecoratorContext` object and supplies it as the first parameter to the wrapper callback.

---

## Properties

| Property | Type | Description |
| :--- | :--- | :--- |
| **`Name`** | `string` | The string tag name of this decorator (e.g. `"adminOnly"`, `"priority"`). |
| **`Arguments`** | `{ any }` | An array containing all arguments passed to this decorator in the annotation comment. |
| **`Parent`** | `DecoratorContext?` | The parent context if this decorator is semantically indented under another decorator. |
| **`Method`** | `string` | The name of the function or method being decorated (e.g. `"Attack"`, `"Init"`). |
| **`Instance`** | `Node?` | The virtualized [`Node`](./node) instance representing the module script defining the method. |
| **`Ancestors`** | `{ any }` | Array of all decorator records declared in the method's docstring header. |
| **`OriginalFunction`**| `function` | The untouched, un-wrapped original Luau function. |
| **`WrappedFunction`** | `function` | The function as transformed by preceding decorators or child wrappers in the pipeline. |
| **`Content`** | `table` | The module's exported container table. |

---

## Methods Summary

| Method | Parameters | Return Type | Description |
| :--- | :--- | :--- | :--- |
| **`GetChildren`** | `` | `{ DecoratorContext }` | Returns all child decorator contexts indented under this decorator. |
| **`FindFirstChild`** | `name: string` | `DecoratorContext?` | Finds the first child decorator context matching the given name. |
| **`IsDescendantOf`** | `parentName: string` | `boolean` | Checks whether this decorator is nested inside a parent decorator with the given name. |

---

## Detailed Methods

<Method name="GetChildren" parameters="" returns="{ DecoratorContext }" scope="Shared">
  Returns an array of child `DecoratorContext` objects that were semantically indented under this decorator in the block comment.

  ### Returns
  * `{ DecoratorContext }`: List of child decorator contexts.

  ### Example
  ```luau
  -- Block comment with semantic indentation:
  --[=[
      @security
          @adminOnly
          @cooldown 5
  ]=]
  function ShopService:BuyItem(player, itemId) end
  ```
</Method>

<Method name="FindFirstChild" parameters="name: string" returns="DecoratorContext?" scope="Shared">
  Finds a direct child decorator context matching `name`.

  ### Parameters
  * `name`: The decorator tag name to look for.

  ### Returns
  * `DecoratorContext?`: The child context, or `nil` if not present.
</Method>

<Method name="IsDescendantOf" parameters="parentName: string" returns="boolean" scope="Shared">
  Traverses the decorator parent hierarchy and returns `true` if any ancestor decorator matches `parentName`.

  ### Parameters
  * `parentName`: The ancestor decorator tag name (e.g. `"client"` or `"server"`).

  ### Returns
  * `boolean`: `true` if this decorator is indented within `parentName`.
</Method>

---

## Writing Custom Decorators

Custom decorators are registered using `game:RegisterDecorator()`. The wrapper callback receives the `DecoratorContext`, the `targetFunction`, and any decorator arguments:

```luau
local __=_G() local RateLimitPlugin = {}

-- Register the "@cooldown <seconds: number>" decorator
game:RegisterDecorator("cooldown", function(context, targetFunc, cooldownSeconds: number)
    local cooldowns = {}
    local duration = cooldownSeconds or 1

    return function(self, player: Player, ...)
        local now = os.clock()
        local lastTime = cooldowns[player] or 0

        if now - lastTime < duration then
            warn(`[Cooldown]: Method '{context.Method}' called too fast by {player.Name}`)
            return
        end

        cooldowns[player] = now
        return targetFunc(self, player, ...)
    end
end)

return __(RateLimitPlugin)
```

### Applying the Custom Decorator
```luau
--[=[
    @cooldown 2.5
]=]
function SpellService:CastSpell(player: Player, spellId: string)
    print(`{player.Name} successfully cast spell {spellId}`)
end
```
