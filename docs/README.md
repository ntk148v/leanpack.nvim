# parcel.nvim Documentation

Welcome to the parcel.nvim documentation. This folder contains comprehensive guides for using parcel.nvim as your Neovim plugin manager.

## Table of Contents

| Document                              | Description                                  |
| ------------------------------------- | -------------------------------------------- |
| [Getting Started](getting-started.md) | Quick start guide to get parcel.nvim running |
| [Installation](installation.md)       | Detailed installation options                |
| [Configuration](configuration.md)     | All configuration options                    |
| [Plugin Spec](spec.md)                | Complete plugin specification reference      |
| [Lazy Loading](lazy-loading.md)       | Lazy loading triggers and patterns           |
| [Commands](commands.md)               | CLI commands reference                       |
| [API](api.md)                         | Lua API reference                            |
| [Migrating](migrating.md)             | Migration guides from other managers         |
| [Troubleshooting](troubleshooting.md) | Common issues and solutions                  |

## Quick Links

- **GitHub**: https://github.com/ntk148v/parcel.nvim
- **Requirements**: Neovim 0.12+
- **License**: MIT

## Overview

parcel.nvim is a minimal, lazy-loading plugin manager for Neovim 0.12+ that acts as a thin layer over the native `vim.pack` API. It provides:

- **Lazy-loading** - Load plugins on demand via events, commands, keymaps, or filetypes
- **Dependency resolution** - Automatic topological sorting for plugin dependencies
- **Build hooks** - Run commands on install/update
- **Native UI** - Simple floating window for plugin management
- **Logging** - Diagnostic logs for debugging

## Key Features

- **Thin Layer**: Delegates all disk operations to vim.pack
- **Zero Overhead**: No package.loaders interception
- **Native Lockfile**: Uses nvim-pack-lock.json
- **lazy.nvim Compatible**: Most specs work without modification
- **Fast**: O(V + E) dependency resolution
