---
title: "Globals"
description: "Comprehensive reference for all global functions and variables injected, overridden, or extended by Nodeal."
category: "API Reference"
order: 1
---

The Nodeal virtualization layer overrides and extends standard Luau globals. Inside every module running within the framework, these functions and symbols are injected directly into the sandboxed global scope (`_G`), providing transparent proxying, advanced type resolution, memory safety, and source-level call tracing.

---

## Dependency & Module Resolution

<Method name="require" parameters="module: string | Node | ModuleScript" returns="any?" scope="Shared">
  An enhanced, virtualized drop-in override for Roblox's native <code class="language-lua">require()</code>. It accepts registered module names as strings, virtualized <code class="language-lua">Node</code> instances, or standard Roblox <code class="language-lua">ModuleScript</code> objects.

  ### Resolution Pipeline
  1. **String Lookup**: If a string name is provided, `require` searches for a matching registered module first. If not found among modules, it automatically checks registered services.
  2. **Node Lookup**: If a virtual `Node` object is passed, it returns its loaded content table.
  3. **Instance Lookup**: If a standard Roblox `Instance` is provided, it resolves through Nodeal's registry before falling back to native engine <code class="language-lua">require()</code>.

  ### Parameters
  * `module`: The target module identifier, virtual `Node`, or `ModuleScript` instance.

  ### Returns
  * `any?`: The loaded module content, or `nil` if resolution fails.

  ### Example
  ```luau
  local __=_G() local ConsumerService = {}

  -- 1. Require by registered string name (location-agnostic)
  local DataService = require("DataService")

  -- 2. Require a virtual Node resolved via game:GetModule()
  local InventoryNode = game:GetModule("InventoryModule")
  local Inventory = require(InventoryNode)

  return __(ConsumerService)
  ```
</Method>

---

## Object Virtualization & Metatables

<Method name="newproxy" parameters="object?: any, force?: boolean" returns="Proxy | userdata" scope="Shared">
  Constructs a secure metatable-driven proxy wrapper around any native Roblox engine object, table, or userdata. When passed `nil` or a boolean, it delegates directly to native Luau <code class="language-lua">newproxy()</code>.

  When wrapping an object or table, the resulting `Proxy` intercepts indexing (<code class="language-lua">__index</code>) and assignments (<code class="language-lua">__newindex</code>) before forwarding them to the underlying target.

  ### Metatable Interception
  Proxies created with `newproxy` support:
  * **`__index`**: Custom function or table to intercept property reads. If the property does not exist on the proxy or metatable, it safely accesses the underlying object.
  * **`__newindex`**: Intercepts property assignments. Writes to an internal `extended` table if the underlying Roblox instance property is read-only or does not exist.
  * **`__setmetatable`**: Custom callback invoked when `setmetatable()` is called on the proxy.
  * **`__getmetatable`**: Custom callback returning a secured metatable when `getmetatable()` is called.
  * **`__type`**: Custom string or function evaluated by `typeof()`.

  ### Parameters
  * `object`: Optional target object, table, or boolean flag.
  * `force`: Optional boolean to re-wrap an existing `Proxy` instance.

  ### Returns
  * `Proxy | userdata`: The virtualized proxy wrapper or native userdata.

  ### Example
  ```luau
  local __=_G() local ServiceWrapper = {}

  -- Intercept property reads on a Roblox engine instance
  local RealPart = Instance.new("Part")
  local ProxyPart = newproxy(RealPart)

  local meta = getmetatable(ProxyPart)
  meta.__index = function(self, key)
      if key == "CustomTag" then
          return "VirtualizedPart"
      end
      return RealPart[key]
  end

  print(ProxyPart.CustomTag) -- "VirtualizedPart"
  print(ProxyPart.Position)  -- Vector3.new(0, 0, 0) (read from RealPart)

  return __(ServiceWrapper)
  ```
</Method>

<Method name="typeof" parameters="value: any, ...acceptedTypes: string | {string}" returns="string?" scope="Shared">
  An enhanced version of Luau's native <code class="language-lua">typeof()</code> that respects custom metatable types (<code class="language-lua">__type</code>) and supports **multi-type candidate matching**.

  ### Custom `__type` Metamethod
  If the value is a table or userdata whose metatable defines `__type`, `typeof` evaluates that field:
  * If `__type` is a string, it returns that string (e.g. `"Node"` or `"DecoratorContext"`).
  * If `__type` is a function, it executes `__type(value)` and returns the resulting type string.

  ### Multi-Type Matching
  If additional arguments are passed, `typeof` validates whether the resolved type matches any of the candidate types:
  * Passing individual strings: `typeof(value, "string", "number")` returns `"string"` or `"number"` if matched, or `nil` if neither.
  * Passing an array of strings: `typeof(value, { "string", "number" })` performs the same candidate check.

  ### Parameters
  * `value`: The target value whose type is being evaluated.
  * `...acceptedTypes`: Optional candidate type strings or arrays of type strings to test against.

  ### Returns
  * `string?`: The resolved type name, or `nil` if candidate matching failed.

  ### Example
  ```luau
  local __=_G() local TypeChecker = {}

  -- 1. Custom __type on OOP class
  local CustomClass = {}
  local instance = setmetatable({}, { __type = "CustomClass" })
  print(typeof(instance)) -- "CustomClass"

  -- 2. Multi-type matching overload
  local id: any = 12345
  if typeof(id, "string", "number") then
      print("id is either a string or a number!")
  end

  local isInvalid = typeof(id, { "boolean", "table" }) == nil
  print(isInvalid) -- true
  ```
</Method>

<Method name="unpack" parameters="target: table | Userdata | Node, start?: number, finish?: number" returns="...any" scope="Shared">
  An enhanced version of Luau's <code class="language-lua">table.unpack()</code> that adds first-class support for virtual objects implementing the custom <code class="language-lua">__unpack</code> metamethod.

  For instance, calling `unpack(node)` on a virtual Node invokes `Node.__unpack(node)`, cleanly extracting the underlying Roblox engine `Instance`.

  ### Parameters
  * `target`: The table, userdata, or `Node` to unpack.
  * `start`: Optional starting index (defaults to `1`).
  * `finish`: Optional ending index (defaults to length of target).

  ### Returns
  * `...any`: The unpacked tuple of values.

  ### Example
  ```luau
  local __=_G() local Unpacker = {}

  -- Unpacking a Node extracts its underlying Roblox Instance
  local MyNode = game:GetModule("PlayerData")
  local RealInstance = unpack(MyNode)

  print(typeof(RealInstance)) -- "Instance"
  return __(Unpacker)
  ```
</Method>

<Method name="setmetatable" parameters="tbl: table, mt: table" returns="table" scope="Shared">
  An overridden version of the native <code class="language-lua">setmetatable()</code>. If the target table's existing metatable implements the custom <code class="language-lua">__setmetatable</code> function, Nodeal routes the execution through it. Otherwise, it delegates to Luau's native `setmetatable`.

  ### Parameters
  * `tbl`: The target table whose metatable is to be set.
  * `mt`: The new metatable table.

  ### Returns
  * `table`: The target table.
</Method>

<Method name="getmetatable" parameters="tbl: table" returns="table?" scope="Shared">
  An overridden version of the native <code class="language-lua">getmetatable()</code>. Respects the custom <code class="language-lua">__getmetatable</code> function on virtualized proxy objects, allowing framework systems and developer libraries to secure internal metatables from extraction.

  ### Parameters
  * `tbl`: The target table or userdata.

  ### Returns
  * `table?`: The metatable or the value returned by `__getmetatable`.
</Method>

---

## Output & Logging Controls

Nodeal intercepts standard logging functions to provide **Source Call Tracing** and **Production Log Privacy** configured via the `Manifest` attributes.

<Method name="print" parameters="...any" returns="void" scope="Shared">
  A wrapped version of Roblox's global <code class="language-lua">print()</code>.
  
  * **Source Tracing**: In Studio and development environments, Nodeal automatically prepends `[ScriptFullName:Line:]` to the output for instant debugging.
  * **Production Suppression**: If the game is running in production and the manifest attribute `PrivatePrint` is set to `true`, `print()` yields silently, preventing client log snooping.

  ### Parameters
  * `...any`: Comma-separated values to log to output.
</Method>

<Method name="warn" parameters="...any" returns="void" scope="Shared">
  A wrapped version of Roblox's global <code class="language-lua">warn()</code>.
  
  * **Source Tracing**: Automatically prepends `[ScriptFullName:Line:]` to the warning banner.
  * **Production Suppression**: If `PrivateWarn` is active in production, warnings are suppressed to prevent console log leaks.

  ### Parameters
  * `...any`: Comma-separated values to format as a warning.
</Method>

<Method name="error" parameters="message?: string, level?: number" returns="void" scope="Shared">
  A wrapped version of Roblox's global <code class="language-lua">error()</code>.
  
  * **Production Defense**: If the manifest attribute `PrivateError` is active in production, this call immediately invokes `coroutine.yield()` to permanently freeze the offending thread without exposing an exploitable error trace to the client console.
  * **Call Stack Alignment**: Adjusts the stack level by `+1` so stack traces pinpoint the exact developer call site rather than the Nodeal virtualization wrapper.

  ### Parameters
  * `message`: Optional error message string.
  * `level`: Optional stack level (defaults to `1` relative to the caller).
</Method>

<Method name="assert" parameters="value: T?, message?: string, level?: number" returns="T" scope="Shared">
  A wrapped version of Roblox's global <code class="language-lua">assert()</code>. If `value` is `nil` or `false`, it throws a formatted Nodeal error, aligning stack levels to the exact failure point.

  ### Parameters
  * `value`: The condition or value to assert.
  * `message`: Optional error message (defaults to `"assertion failed!"`).
  * `level`: Optional stack level (defaults to `2`).

  ### Returns
  * `T`: The evaluated truthy value.
</Method>

<Method name="debug" parameters="" returns="Proxy<debug>" scope="Shared">
  A proxied wrapper around Luau's native `debug` library. In addition to standard debug functions (`debug.info`, `debug.traceback`, etc.), it exposes the framework's custom output primitives as:
  * `debug.print(...)`
  * `debug.warn(...)`
  * `debug.error(message?, level?)`
  * `debug.assert(value, message?, level?)`
</Method>

---

## Virtual Scope & Handshake Variables

Inside every Nodeal module, two critical framework identifiers are exposed directly in scope:

### `script` (Class: [Node](./node))
Inside a standard Roblox `ModuleScript`, the `script` variable refers to the native Roblox `Instance`. In Nodeal, `script` is virtualized into a **`Node`** object:
* Accessing `script.Name`, `script.Parent`, `script.Children` interacts with the virtual dependency tree.
* Provides framework methods such as `script:GetCollected("tag")` and `script:GetCalls()`.
* Automatically forwards engine calls (like `script:GetChildren()`) to the underlying Roblox instance.

### `_G` (The Handshake Hook)
In vanilla Luau, `_G` is a shared global table. In Nodeal, calling `_G()` executes the **Security Handshake Accessor**:
```luau
local __=_G() local MyModule = {}
-- ...
return __(MyModule)
```
Calling `_G()` captures caller metadata, verifies that the script is executing within a valid framework root, sets the module's sandboxed environment via `setfenv`, and returns the registration closure that applies decorators and protects module memory.
