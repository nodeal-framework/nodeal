---
title: "Packages"
description: "Discover, install, create, and publish version-controlled community packages directly from Roblox Studio with Nodeal Packages."
category: "Packages"
order: 11
---

Nodeal includes a full-featured, **studio-native package manager**. Unlike traditional Roblox package managers (like Wally or NPM) that require external terminal tooling, configuration files (`wally.toml`), and synchronization daemons, Nodeal Packages are managed **100% visually inside Roblox Studio**.

---

## Overview & Architecture

| Environment | Key Capabilities |
| :--- | :--- |
| **Roblox Studio Plugin** | • Browse and search package registry<br/>• One-click install and version updates<br/>• Smart-merge file integrator (preserves local modifications)<br/>• In-Studio package publishing and uploads |
| **Web Dashboard (nodeal.dev)** | • Central package registry and version index<br/>• Community documentation and showcase<br/>• Account and authentication token management |

### Why Studio-Native Package Management?
* **Zero Command-Line Setup**: No terminal, Git, or CLI package managers required.
* **Instant In-Studio Discovery**: Search and preview packages directly within the Studio **Packages Widget**.
* **Smart Merging**: Installing package updates updates library logic without destroying your place configuration or custom modifications.
* **Seamless Dependency Resolution**: Packages integrate natively with `game:GetService()` and `game:GetModule()`.

---

## Using the Packages Widget

To open the package manager, click the **Packages** icon in the **Nodeal** ribbon tab in Roblox Studio.

### The Browse Tab
Explore trending, official, and community-published packages. Packages are badged with verified status, download counts, and target compatibility.

### The Search Tab
Filter packages by keyword, category (e.g. `Combat`, `Networking`, `UI`, `Analytics`), or specific author.

### Package Details & Versions
Clicking on any package displays:
* **Package Description & Readme**: Full markdown documentation embedded in the widget.
* **Version Selector**: Switch between the latest release or pin to an older version.
* **Dependencies**: Inspect external libraries required by the package.

### Installing a Package
1. Select the package in the widget.
2. Choose your desired version (defaults to latest).
3. Click **Install**.
4. The plugin automatically downloads the package assets and installs them into the appropriate `Source` directory.

---

## Anatomy of a Nodeal Package

A Nodeal package is a standardized folder asset managed by the internal `Packager` engine:

- **`MyPackage`** *(Folder)*
  - **`Source`** *(Folder or ModuleScript)* — Contains the functional Luau modules and services.
  - **`Profiles`** *(Folder, Optional)* — Configuration templates (e.g. `Default`, `Production`).
  - **`Manifest`** *(Configuration)* — Metadata attributes:
    - `PackageId`: Unique package string (e.g. `"my-package-id"`).
    - `Version`: Semantic version string (e.g. `"1.0.0"`).
    - `Author`: Creator handle or studio name.

### Package Components
* **`Source`**: The functional Luau code containing your modules and services.
* **`Profiles`**: Optional configuration templates. When a package is installed, users can select a profile (e.g. `Lightweight`, `Full`, `Production`) to pre-configure behavior.
* **`Variables`**: Packages can define variable substitution tokens (e.g. `{{DATABASE_NAME}}` or `{{COOLDOWN_DEFAULT}}`) that are dynamically populated during installation.

---

## Authoring & Publishing Packages

You can publish your own libraries, systems, or tools to the Nodeal registry directly from Roblox Studio:

<Steps>
  <Step title="Sign in with Your Nodeal Account">
    1. Click the **Account** widget icon in the Nodeal ribbon.
    2. Sign in with your **[nodeal.dev](https://www.nodeal.dev)** developer credentials.
    3. Your avatar and account status will display in the ribbon.
  </Step>

  <Step title="Prepare Your Package Folder">
    1. Organize your package code inside a single root folder in Explorer.
    2. Ensure all scripts adhere to the virtualization boilerplate (`local __=_G()` and `return __(module)`).
    3. Document your public methods using Luau block comments (`--[=[ ... ]=]`).
  </Step>

  <Step title="Publish via the Upload Controller">
    1. Select your package root folder in the Roblox Studio Explorer.
    2. In the **Packages** widget, navigate to the **Upload** panel.
    3. Enter your package identifier, display name, version number, and description.
    4. Click **Publish Package**. The plugin serializes the asset, uploads it to the registry, and indexes it for the community!
  </Step>
</Steps>
