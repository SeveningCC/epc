# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

EPC (El Pkg Congroo) is a package manager for [CC:Tweaked](https://tweaked.cc/), a Minecraft mod that adds Lua-programmable computers. The entire program is a single Lua file (`epc.lua`) that runs inside the in-game environment.

## Development

Copy `epc.lua` into the CC:Tweaked computer to test it live:

```
make dev
```

The `makefile` hardcodes the destination to a specific PrismLauncher save (`~/.local/share/PrismLauncher/instances/Primos CCC v1.3.0/...`). There are no automated tests — all testing is manual inside the game.

To install EPC from scratch on a CC:Tweaked computer:

```
wget run https://raw.githubusercontent.com/SeveningCC/epc/refs/heads/main/install.lua
```

## Architecture

**`epc.lua`** — the entire runtime, structured in layers:

- **`FILE_TYPES`**: maps the three supported file categories to their install paths, each overridable via CC settings:
  - `bin` → `epc.path.bin` (default `/pkgs`) — executables; also added to `shell.path` persistently
  - `startup` → `epc.path.startup` (default `/startup`)
  - `autocomplete` → `epc.path.autocomplete` (default `/sys/autocomplete`)
- **Registry** (`/.local/epc/packages`): a `textutils.serialize`d table tracking installed packages (owner, repo, tag, flat list of installed file paths, deps). Loaded/saved per command.
- **`Package`**: fetches `package.json` from a GitHub repo via raw.githubusercontent.com, then downloads each listed file via the GitHub Contents API (which returns base64-encoded content decoded with `cc.base64`). Directories are traversed recursively. Dual-use: when built from GitHub data it holds typed source arrays (`bin`, `startup`, `autocomplete`); when built from registry data via `instantiate_from_data` it holds `files` (actual installed paths, used for uninstall).
- **Commands** (`install`, `uninstall`, `update`, `list`): thin wrappers over `Package` and `registry`. `install` also recursively installs dependencies, skipping already-installed ones.
- **Public API**: when `require`d (detected via `type((...)) == "string"`), returns `{ install, uninstall, update, list, Package, registry }` and skips the CLI/autocomplete blocks entirely.
- **Autocomplete**: registered with `shell.setCompletionFunction` so `uninstall`/`update` tab-complete installed package IDs.

**`install.lua`** — a bootstrap-only script. Bypasses EPC's own install logic (since EPC isn't installed yet) by directly fetching `epc.lua` via raw GitHub URLs, adding `/pkgs` to `shell.path` persistently via `settings`, and manually writing the EPC entry into the registry so `epc update SeveningCC/epc` works afterwards.

**`package.json`** — EPC's own package manifest. EPC is a valid EPC package and is self-managed after bootstrapping.

## Package format

A package is a GitHub repository with a `package.json` at the root. Files are declared by category:

```json
{
  "name": "...",
  "version": "...",
  "description": "...",
  "bin": ["program.lua"],
  "startup": ["my-startup.lua"],
  "autocomplete": ["my-ac.lua"],
  "dependencies": ["owner/repo@tag"]
}
```

All sections are optional — a package can have only `bin`, only `startup`, or any combination. Package IDs use the format `owner/repo[@tag]`. Tag defaults to `main`; `latest` is also treated as `main`. Tags resolve to `refs/tags/<tag>`, `main` resolves to `refs/heads/main`.

## CC:Tweaked API notes

- `fs`, `http`, `shell`, `settings`, `textutils` — CC globals, not standard Lua
- `cc.base64` and `cc.completion` / `cc.shell.completion` — CC built-in modules
- `textutils.serialize` / `unserialize` — CC's table serialization (not JSON)
- `textutils.unserializeJSON` — used only for GitHub API responses and `package.json`
