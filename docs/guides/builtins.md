---
title: "Built-ins"
description: "Extend the Luau language and inject framework-wide global utilities using Nodeal Built-ins."
category: "Modules"
order: 7
---

**Built-ins** are stateless utility libraries or language extensions injected directly into Nodeal's virtualized global environment (`universe`).

Unlike Services (which are singletons retrieved using `game:GetService()`), Built-ins are **first-class globals** available to all virtualized modules without requiring any `require()` or lookup statements.

---

## Global Injection

Built-ins are registered using the <code class="language-lua">game:RegisterBuiltIn()</code> method. Once registered, the library becomes globally accessible project-wide:

```luau
local __=_G() local MathEx = {}

-- Pure utility functions
function MathEx.lerp(startValue: number, goalValue: number, alpha: number): number
    return startValue + (goalValue - startValue) * alpha
end

function MathEx.clamp01(value: number): number
    return math.clamp(value, 0, 1)
end

function MathEx.roundTo(value: number, decimalPlaces: number): number
    local factor = 10 ^ decimalPlaces
    return math.round(value * factor) / factor
end

-- Register MathEx as a global Built-in
game:RegisterBuiltIn("MathEx", MathEx)

return __(MathEx)
```

In any other module script within your project, `MathEx` is available directly as a global:

```luau
local __=_G() local MoverModule = {}

function MoverModule:Step(part: BasePart, targetPosition: Vector3, deltaTime: number): ()
    -- MathEx is available globally with zero imports!
    local currentPos = part.Position
    local newX = MathEx.lerp(currentPos.X, targetPosition.X, deltaTime * 5)
    local newY = MathEx.lerp(currentPos.Y, targetPosition.Y, deltaTime * 5)
    local newZ = MathEx.lerp(currentPos.Z, targetPosition.Z, deltaTime * 5)

    part.Position = Vector3.new(newX, newY, newZ)
end

return __(MoverModule)
```

> [!IMPORTANT]
> **Sandboxed Global Scope**  
> Built-in globals are only injected into scripts executing inside the Nodeal virtualization layer. Standard, non-virtualized Roblox scripts (such as legacy scripts in `Workspace`) will not have access to these globals and will remain completely unaffected.

---

## Standard Library Extension

Nodeal's most powerful language feature is the ability to safely extend or override standard Luau libraries (like `math`, `os`, `table`, or `string`) without polluting Roblox's native C++ engine environment.

### Example: Enhancing the `os` Library
We can wrap the standard `os` library in a proxy and redirect `os.time()` to return high-precision, synchronized server time via `workspace:GetServerTimeNow()`, while keeping all other native functions (`os.date`, `os.difftime`) intact:

```luau
local __=_G()

-- Wrap the native os library in a virtual proxy object
local BetterOS = newproxy(os)

-- Override the time method to return synchronized server time
function BetterOS.time(): number
    return math.floor(workspace:GetServerTimeNow())
end

-- Add a high-precision millisecond timestamp method
function BetterOS.timeMs(): number
    return workspace:GetServerTimeNow() * 1000
end

-- Register as "os" to override the standard Luau global
game:RegisterBuiltIn("os", BetterOS)

return __(BetterOS)
```

### Example: Extending the `table` Library
Add functional programming helpers (like `map`, `filter`, `find`) directly to the `table` global:

```luau
local __=_G()

local BetterTable = newproxy(table)

function BetterTable.map<T, U>(sourceArray: { T }, mapFunction: (item: T, index: number) -> U): { U }
    local result = table.create(#sourceArray)
    for index, value in sourceArray do
        result[index] = mapFunction(value, index)
    end
    return result
end

function BetterTable.filter<T>(sourceArray: { T }, predicateFunction: (item: T) -> boolean): { T }
    local result = {}
    for _, value in sourceArray do
        if predicateFunction(value) then
            table.insert(result, value)
        end
    end
    return result
end

game:RegisterBuiltIn("table", BetterTable)

return __(BetterTable)
```

> [!WARNING]
> **Backward Compatibility**  
> When overriding standard Luau libraries, always use `newproxy(nativeLibrary)` so unhandled calls fall back to native engine implementations. Never replace a standard library table with an empty dictionary.