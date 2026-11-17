---
title: "Node"
description: "API Reference for the Node class, the virtualized instance wrapper representing scripts and hierarchy elements in Nodeal."
category: "API Reference"
order: 3
---

The **`Node`** class is Nodeal's virtualized representation of Roblox `Instance` and `ModuleScript` objects.

Inside every virtualized module, the global **`script`** variable resolves to a `Node` instance rather than a raw Roblox engine `ModuleScript`. Furthermore, root traversal, child lookups, and `game:GetModule()` operate on or return `Node` objects.

> [!NOTE]
> `Node` seamlessly forwards engine properties and methods to its underlying Roblox `Instance`. If you index a property or invoke an engine method not implemented on `Node` (e.g. `script.Parent`, `script:GetChildren()`), the call is transparently executed on the underlying engine object.

---

## Properties

| Property | Type | Description |
| :--- | :--- | :--- |
| **`Instance`** | `Instance` | The underlying native Roblox engine `Instance` wrapped by this node. |
| **`Children`** | `{ (Node \| Instance)? }` | Array of child `Node` instances belonging to this node. |
| **`Parent`** | `(Node \| Instance)?` | The parent `Node` or Roblox `Instance`. |
| **`Name`** | `string` | The string identifier of this node. |
| **`FullName`** | `string` | Hierarchical dot-separated full path of this node (e.g. `ReplicatedStorage.Source.MyModule`). |
| **`Attributes`** | `{[string]: any}` | Internal attribute dictionary storing serialized metadata and custom attributes. |
| **`Content`** | `any?` | The exported module content table, populated once the module executes its handshake. |
| **`Collected`** | `{[string]: {CollectedItem}}?` | Cached dictionary of collected decorator entries parsed from `ContentPayload[".collected"]`. |
| **`Calls`** | `{[string]: any}?` | Static call analysis data parsed from `ContentPayload[".calls"]`. |

---

## Methods Summary

| Method | Parameters | Return Type | Description |
| :--- | :--- | :--- | :--- |
| **`GetCollected`** | `decoratorName?: string` | `{[string]: {CollectedItem}} \| {CollectedItem}` | Retrieves records of all methods annotated with a `@collect`-enabled decorator across the project. |
| **`GetCalls`** | `sourceOrModule?: string` | `{[string]: any}` | Retrieves static call analysis information recorded by the Pre-Parser. |
| **`GetAttribute`** | `attribute: string` | `any?` | Reads an attribute value from the node's attribute storage. |
| **`SetAttribute`** | `attribute: string, value: any?` | `void` | Sets an attribute value on the node. |
| **`GetAttributes`**| `` | `{[string]: any}` | Returns a dictionary containing all attributes assigned to this node. |
| **`GetFullName`** | `` | `string` | Returns the hierarchical path of the node. |
| **`GetChildren`** | `` | `{ (Node \| Instance)? }` | Returns an array of direct children. |
| **`GetDescendants`**| `` | `{ (Node \| Instance)? }` | Recursively traverses and returns all descendant nodes. |
| **`FindFirstChild`**| `index: string, recursive?: boolean` | `(Node \| Instance)?` | Searches for a child node by name, with optional recursive search. |
| **`Clone`** | `` | `Instance` | Clones the underlying native Roblox instance. |
| **`Destroy`** | `` | `void` | Recursively destroys all child nodes and removes the underlying instance. |

---

## Detailed Methods

<Method name="GetCollected" parameters="decoratorName?: string" returns="{[string]: {CollectedItem}} | {CollectedItem}" scope="Shared">
  Retrieves collections of methods across the entire codebase that were tagged with custom decorators registered with the `@collect` directive.

  When a decorator is registered with `@collect`, the Studio Pre-Parser automatically indexes all call sites and method annotations in your project, compiling them into the defining module's `ContentPayload[".collected"]`. At runtime, calling `:GetCollected()` returns these entries wrapped in **`CollectedItem`** proxy objects.

  ### Parameters
  * `decoratorName`: Optional string. If specified, returns an array of `CollectedItem` objects matching that decorator. If omitted, returns a dictionary mapping decorator names to lists of `CollectedItem`s.

  ### Returns
  * `{[string]: {CollectedItem}} | {CollectedItem}`: The collected decorator records.

  ### Example
  ```luau
  local __=_G() local NetworkRouter = {}

  -- Retrieve all methods tagged with @net across all game services
  local netEvents = script:GetCollected("net")
  for _, item in netEvents do
      print(`Found remote event listener: {item.method} on service {item.services[1]}`)
      local service = item:Resolve()
  end

  return __(NetworkRouter)
  ```
</Method>

<Method name="GetCalls" parameters="sourceOrModule?: string" returns="{[string]: any}" scope="Shared">
  Retrieves static call analysis data for this module or an external source. The Pre-Parser tracks method invocation lines and caller metadata to optimize dependency resolution and usage detection.

  ### Parameters
  * `sourceOrModule`: Optional string identifier of the caller module or source name to inspect.

  ### Returns
  * `{[string]: any}`: Dictionary of recorded call sites and line numbers.
</Method>

<Method name="GetAttribute" parameters="attribute: string" returns="any?" scope="Shared">
  Returns the value associated with the specified attribute name on this node.

  ### Parameters
  * `attribute`: The string key of the attribute.

  ### Returns
  * `any?`: The attribute value, or `nil` if not defined.
</Method>

<Method name="SetAttribute" parameters="attribute: string, value: any?" returns="void" scope="Shared">
  Sets the value of an attribute on this node.

  ### Parameters
  * `attribute`: The string key.
  * `value`: The value to assign, or `nil` to remove the attribute.
</Method>

<Method name="GetAttributes" parameters="" returns="{[string]: any}" scope="Shared">
  Returns a shallow copy of all attributes stored on this node.

  ### Returns
  * `{[string]: any}`: Key-value dictionary of attributes.
</Method>

<Method name="GetFullName" parameters="" returns="string" scope="Shared">
  Returns the full dot-delimited path of the node within the virtual hierarchy.

  ### Returns
  * `string`: E.g. `"ReplicatedStorage.Source.Combat.HitboxManager"`.
</Method>

<Method name="GetChildren" parameters="" returns="{ (Node | Instance)? }" scope="Shared">
  Returns an array of all direct child `Node` or `Instance` objects attached to this node.

  ### Returns
  * `{ (Node | Instance)? }`: List of child elements.
</Method>

<Method name="GetDescendants" parameters="" returns="{ (Node | Instance)? }" scope="Shared">
  Recursively collects and returns all descendants belonging to this node.

  ### Returns
  * `{ (Node | Instance)? }`: Flattened array of all descendant nodes and instances.
</Method>

<Method name="FindFirstChild" parameters="index: string, recursive?: boolean" returns="(Node | Instance)?" scope="Shared">
  Finds the first child matching the given `index` name. If `recursive` is `true`, performs a depth-first search across all descendants.

  ### Parameters
  * `index`: The name of the child to search for.
  * `recursive`: Optional boolean flag to enable recursive searching.

  ### Returns
  * `(Node | Instance)?`: The matching node or instance, or `nil` if not found.
</Method>

<Method name="Clone" parameters="" returns="Instance" scope="Shared">
  Clones the underlying native Roblox engine `Instance` and sets its name.

  ### Returns
  * `Instance`: The cloned engine instance.
</Method>

<Method name="Destroy" parameters="" returns="void" scope="Shared">
  Recursively destroys all child nodes, detaches the node from its parent, destroys the underlying Roblox `Instance`, and clears metatable references.
</Method>

---

## Metamethods

* **`__index(self, index)`**:
  1. Checks if `index` matches any method or field on `Node`.
  2. If not, attempts to index `self.Instance[index]`. If the returned value is a method, wraps it so `self` correctly forwards `self.Instance`.
  3. If property indexing fails, delegates to `self:FindFirstChild(index)`.
* **`__newindex(self, key, value)`**:
  Attempts to assign `self.Instance[key] = value`. If the property does not exist on the Roblox instance, stores it directly on the node table.
* **`__unpack(self)`**:
  Returns the underlying Roblox engine `Instance`.
* **`__tostring(self)`**:
  Returns `tostring(self.Instance)`.
* **`__type`**:
  Returns `"Node"`, allowing `typeof(node)` to evaluate to `"Node"`.
  