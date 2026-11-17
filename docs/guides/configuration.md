---
title: "Configuration"
description: "Reference guide for the Nodeal runtime Manifest, container root tags, context attributes, and environment settings."
category: "Architecture"
order: 12
---

Nodeal provides straightforward configuration options to customize runtime optimization, logging privacy, root container discovery, and environment scoping.

Most settings are declared as **Roblox Attributes** on the runtime **`Manifest`** object and root folder containers.

---

## Runtime Manifest

The runtime uses a `Configuration` instance named `Manifest` located under its hierarchy:

* `ReplicatedStorage`
  * `Global` *(Folder)*
    * `Runtime` *(Script)*
      * `Manifest` *(Configuration)*

### Manifest Attributes

| Attribute | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| **`TagRoot`** | `string` | `"NodealRoot"` | The `CollectionService` tag used by the bootstrapper to discover framework root folders. |
| **`OptimizeProduction`** | `boolean` | `true` | When active outside Studio: disables debug callsite trace generation and shortens internal identifier strings for speed. |
| **`PrivatePrint`** | `boolean` | `true` | When running in production: suppresses all `print()` outputs to prevent client log leaks. |
| **`PrivateWarn`** | `boolean` | `true` | When running in production: suppresses all `warn()` outputs in live games. |
| **`PrivateError`** | `boolean` | `true` | When running in production: raises a bare error (no message, no trace) instead of exposing stack traces to players. |
| **`IntegrityWatch`** | `boolean` | `false` | Opt-in client watchdog: every 5 seconds, re-checks that the sealed tables are still frozen, the metatables were not swapped and tracked functions kept their source. Only required if your game needs active tamper detection. |

---

## Root Container Attributes

Any folder in your game can be designated as a Nodeal root container by tagging it with the `TagRoot` tag (e.g. using Roblox Studio's Tag Editor or the Nodeal Setup wizard).

Root containers support the following attributes:

| Attribute | Type | Description |
| :--- | :--- | :--- |
| **`ContextServer`** | `boolean` | When `true`, this root container and its children will only be loaded and executed on the **Server**. |
| **`ContextClient`** | `boolean` | When `true`, this root container and its children will only be loaded and executed on the **Client**. |
| **`PriorityServer`** | `number` | Overrides the default execution priority order for modules in this container when loading on the server. |
| **`PriorityClient`** | `number` | Overrides the default execution priority order for modules in this container when loading on the client. |

---

## Module Attributes

During editing in Studio, the background Pre-Parser serializes metadata directly onto each `ModuleScript`:

| Attribute | Type | Description |
| :--- | :--- | :--- |
| **`ContentHeader`** | `string` | Serialized array of module-level decorators (`@priority`, `@server`, `@client`). |
| **`ContentPayload`** | `string` | Serialized dictionary of method-level decorators and collection endpoints. |
| **`ResolvedPriority`** | `number` | Topological sorting order calculated from static dependencies. |
| **`ContentExcluded`** | `boolean` | When `true`, instructs the runtime to skip this module during execution. |

---

## Execution Contexts

Nodeal modules run in one of three contexts based on their physical placement or docblock tags:

| Context | Recommended Location | Scoping Decorator | Behavior |
| :--- | :--- | :--- | :--- |
| **Server** | `ServerStorage` or `ServerScriptService` | `@server true` | Runs exclusively on the game server. Never sent to clients. |
| **Client** | `StarterPlayerScripts` | `@client true` | Runs locally on the client machine. Never executed on the server. |
| **Shared** | `ReplicatedStorage` | *(Default for shared folders)* | Replicated and available in both Server and Client environments. |
