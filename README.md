<div align="center">

# Nodeal

**A modern development workflow for Roblox, without leaving Studio.**

Sandboxed modules, dependency injection, comment decorators, typed autocomplete,
inline diagnostics and a package manager.

![Status](https://img.shields.io/badge/status-early%20access-orange)
[![Roblox](https://img.shields.io/badge/Roblox-Studio-00A2FF?logo=roblox&logoColor=white)](https://www.nodeal.dev)
[![Luau](https://img.shields.io/badge/runtime-Luau-2C2D72)](https://www.nodeal.dev/docs)
[![License](https://img.shields.io/badge/license-Nodeal%20Public-blue)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white)](https://discord.gg/hTqXPRduHp)

</div>

## A shared service

```luau
local __=_G() local ShopService = {}

local Config = game:GetModule("Config")

--[=[
    @server
    
    @param player The buyer.
    @param itemId The item to buy.
    @return The new balance, or nil if the purchase failed.
]=]
function ShopService:Buy(player: Player, itemId: string): number?
    local price = Config.Prices[itemId]

    if not price or (player:GetAttribute("Coins") or 0) < price then
        return nil
    end

    local balance = (player:GetAttribute("Coins") or 0) - price

    player:SetAttribute("Coins", balance)

    return balance
end

--[=[
    @return The label shown in the shop UI.
]=]
function ShopService:GetLabel(itemId: string): string
    return Config.Items[itemId].Label
end

game:RegisterService("ShopService", ShopService)

return __(ShopService)
```

`local __=_G()` opens the sandbox and `return __(...)` hands the module to the runtime.
`@server` guards `Buy` to the server, and `@client` restricts `GetLabel` to the client.
`@param` and `@return` feed the Studio hover tooltips. `game:RegisterService` registers
the singleton and `game:GetModule("Config")` resolves the config by name.

## A controller

```luau
local __=_G() local ShopController = {}

local Network = game:GetService("Network")
local ShopService = game:GetService("ShopService")
local Buttons = game:GetModule("ShopButtons")

--[=[
    @debounce 0.3
]=]
function ShopController:Buy(itemId: string): ()
    print(`Buying {ShopService:GetLabel(itemId)}`)

    Network:FireServer("Buy", itemId)
end

function ShopController.Init(): ()
    for _, button in Buttons do
        button.Activated:Connect(function()
            ShopController:Buy(button:GetAttribute("ItemId"))
        end)
    end
end

return __(ShopController)
```

`@debounce 0.3` is a project decorator, registered once with `game:RegisterDecorator`:
clicks within 300ms of each other are dropped. `Init` sits last by convention and runs
after every module has built, so `Network`, `ShopService` and `Buttons` are ready.
`GetLabel` only runs on the client, where this controller lives.

## Install

1. Go to [nodeal.dev/get-nodeal](https://www.nodeal.dev/get-nodeal) and install the
   plugin from its Roblox page.
2. Open Roblox Studio. The plugin shows up in the **Plugins** tab.
3. Open the **Nodeal** tab and click **Setup**. The plugin creates the runtime folders,
   tags them, and adds the client and server entry points.

The full walkthrough is in [docs/guides/getting-started.md](docs/guides/getting-started.md).

## What's inside

- **Virtualized runtime.** Each module runs in its own sandbox. `require`, `print`,
  `script` and the rest are overridden inside it.
- **Deterministic lifecycle.** `Build` runs as modules load, `Init` runs once everything
  is ready, and load order is derived from static dependencies.
- **Dependency injection.** Custom singletons and native Roblox services both come from
  `game:GetService`.
- **Modules by name.** `game:GetModule("Config")` survives file moves and resolves
  circular dependencies.
- **Decorators in comments.** 17 built-in decorators for context, lifecycle, docs,
  autocomplete and metaprogramming. No build step.
- **Studio toolchain.** Custom explorer, typed autocomplete, inline diagnostics and a
  package manager.
- **Passive security.** Native `require` returns `nil`, client scripts are detached after
  loading, and production logs are stripped.

## Repository

```
packages/
  plugin/   Studio plugin: explorer, pre-parser, autocomplete, diagnostics, packages
  runtime/  In-game runtime: sandbox, registries, lifecycle
docs/       Guides and references
```

The repository follows the [Rovue](https://github.com/furymob-git/rovue) structure. You
don't need it to use Nodeal, only to build the packages from source.

## Documentation

- [Getting started](docs/guides/getting-started.md)
- [Core concepts](docs/guides/core-concepts.md)
- [Services](docs/guides/services.md)
- [Modules](docs/guides/modules.md)
- [Decorators](docs/guides/decorators.md)
- [Studio integration](docs/guides/studio-integration.md)

## License

Distributed under the **Nodeal Public License (NPL)**. See [`LICENSE`](/LICENSE) for more information.

> **TL;DR:** You generally cannot sell the framework source code itself, but you **CAN** use it to build commercial games, plugins, and modules.
