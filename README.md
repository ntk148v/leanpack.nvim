<div align="center">
  <p><img src="./assets/logo.png" width="20%" height="20%" alt="leanpack.nvim logo"></p>
  <h1>Leanpack.nvim</h1>
</div>
<div align="center">
  <a href="https://github.com/ntk148v/leanpack.nvim/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/ntk148v/leanpack.nvim?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41&include_prerelease&sort=semver" />
  </a>
  <a href="https://github.com/ntk148v/leanpack.nvim/pulse">
    <img alt="Last commit" src="https://img.shields.io/github/last-commit/ntk148v/leanpack.nvim?style=for-the-badge&logo=starship&color=8bd5ca&logoColor=D9E0EE&labelColor=302D41"/>
  </a>
  <a href="https://github.com/ntk148v/leanpack.nvim/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/ntk148v/leanpack.nvim?style=for-the-badge&logo=starship&color=ee999f&logoColor=D9E0EE&labelColor=302D41" />
  </a>
  <a href="https://github.com/ntk148v/leanpack.nvim/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/ntk148v/leanpack.nvim?style=for-the-badge&logo=starship&color=c69ff5&logoColor=D9E0EE&labelColor=302D41" />
  </a>
  <a href="https://github.com/ntk148v/leanpack.nvim/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/ntk148v/leanpack.nvim?style=for-the-badge&logo=bilibili&color=F5E0DC&logoColor=D9E0EE&labelColor=302D41" />
  </a>
</div>

A layer on top of Neovim's native `vim.pack`, adding support for lazy-loading and the widely adopted lazy.nvim-like declarative spec.

**Requirements:** Neovim 0.12+

## Documentation

| Document                                   | Description                             |
| ------------------------------------------ | --------------------------------------- |
| [Getting Started](docs/getting-started.md) | Quick start guide                       |
| [Installation](docs/installation.md)       | Detailed installation options           |
| [Configuration](docs/configuration.md)     | All configuration options               |
| [Plugin Spec](docs/spec.md)                | Complete plugin specification reference |
| [Lazy Loading](docs/lazy-loading.md)       | Lazy loading triggers and patterns      |
| [Commands](docs/commands.md)               | CLI commands reference                  |
| [API](docs/api.md)                         | Lua API reference                       |
| [Migrating](docs/migrating.md)             | Migration guide from lazy.nvim          |

## Quick Start

### Bootstrap

Add this to the top of your `init.lua`:

```lua
-- Setup leanpack.nvim plugin manager
vim.pack.add({ { src = "https://github.com/ntk148v/leanpack.nvim" } })

-- Setup leanpack with import from lua/plugins/
require("leanpack").setup({
    { import = "plugins" },
    defaults = {
        lazy = true,
    },
    performance = {
        vim_loader = true,
        rtp_prune = true,
    },
})
```

### Create Specs

Create your plugin specs in `lua/plugins/`:

```lua
-- lua/plugins/treesitter.lua
return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter.configs').setup({ highlight = { enable = true } })
  end,
}
```

## Why leanpack.nvim over bare `vim.pack`?

`vim.pack` (Neovim 0.12+) is a solid native foundation — leanpack builds on top of it, not around it. Here's what you get:

| Feature                        | bare `vim.pack`                                                 | leanpack.nvim                                                                     |
| ------------------------------ | --------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| **Spec format**                | Raw `vim.pack.add()` calls                                      | lazy.nvim-compatible declarative spec (`'user/repo'`, `opts = {}`, `config = fn`) |
| **Lazy-loading**               | Manual — write your own VimEnter queues and autocmds per plugin | Built-in triggers: `event`, `cmd`, `keys`, `ft`, `module` (require-based)         |
| **Dependencies**               | Manual ordering                                                 | Automatic resolution with topological sort                                        |
| **Build hooks**                | None                                                            | `build = ':TSUpdate'` or `build = function() ... end`                             |
| **Plugin management UI**       | None                                                            | `:Leanpack` floating window with filtering, load/update/delete                    |
| **Install/Update**             | Manual `vim.pack.add()` + restart                               | Background jobs via headless Neovim, no restart needed                            |
| **ftdetect sourcing**          | Manual                                                          | Automatic for lazy-loaded plugins                                                 |
| **Config from multiple files** | Manual `require` chains                                         | `{ import = "plugins" }` auto-discovers `lua/plugins/*.lua`                       |

In short: if you're happy writing ~250 lines of helper code (lazyload queues, deep merge, local dev support) around `vim.pack` for every config, you don't need leanpack. If you want a lazy.nvim-style declarative experience on top of native `vim.pack`, that's exactly what this is.

## Features

- **Native Core**: Builds on top of `vim.pack` — no custom package management, no fork.
- **Lazy-loading**: Load plugins on demand via events, commands, keymaps, filetypes, or `require()`.
- **lazy.nvim Compatible**: Uses the same declarative spec format you already know.
- **Dependency Management**: Automatic resolution and topological loading.
- **Build Hooks**: Run commands or Lua functions on install/update.
- **Performance**: Built-in `vim.loader` integration and RTP pruning.

## Commands

- `:Leanpack` - Open the UI (supports `/` filtering)
- `:Leanpack sync` - Sync all plugins (update + clean)
- `:Leanpack update` - Update all or specific plugin
- `:Leanpack clean` - Remove unused plugins
- `:Leanpack build!` - Run all build hooks
- `:Leanpack load!` - Load all pending plugins

See [Commands](docs/commands.md) for details.

## Configuration

```lua
require('leanpack').setup({
  defaults = {
    confirm = true,
  },
  sync = true, -- Auto-remove plugins no longer in config on startup
  performance = {
    vim_loader = true,
    rtp_prune = true, -- Disable built-in plugins for faster startup
  },
})
```

See [Configuration](docs/configuration.md) for more options.

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with leanpack. Key differences are documented in [Migrating](docs/migrating.md).

- **version pinning**: leanpack's `version` field supports both semantic versioning (e.g., `1.*`) and literal git references (branch/tag/commit).
- **dev mode**: Use `dev = true` with `dir = '~/projects/plugin-name'` for local development
- **optional**: Use `optional = true` for dependencies that won't block plugin loading
- **module trigger**: leanpack automatically supports require()-based lazy loading matching the auto-detected or explicit `main` module names.

## Acknowledgements

- Inspired by [lazy.nvim](https://github.com/folke/lazy.nvim) for the declarative spec design
