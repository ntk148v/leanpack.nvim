<p align="center">
  <img src="assets/logo.png" width="400" alt="leanpack.nvim logo">
</p>

# leanpack.nvim

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
local lazypath = vim.fn.stdpath("data") .. "/site/pack/leanpack/opt/leanpack.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/ntk148v/leanpack.nvim", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("leanpack").setup()
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

## Features

- **Native Core**: Completely leverages the native `vim.pack` infrastructure (Neovim 0.12+).
- **Lazy-loading**: Load plugins on demand via events, commands, keymaps, or filetypes.
- **lazy.nvim Compatible**: Uses the same declarative spec format you know.
- **Dependency Management**: Automatic resolution and topological loading.
- **Build Hooks**: Run commands or Lua functions on install/update.
- **Performance**: Built-in `vim.loader` integration and RTP pruning.

## Commands

- `:Leanpack` - Open the UI
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
  performance = {
    vim_loader = true,
    rtp_prune = true, -- Disable built-in plugins for faster startup
  },
})
```

See [Configuration](docs/configuration.md) for more options.

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with leanpack. Key differences are documented in [Migrating](docs/migrating.md).

- **version pinning**: lazy.nvim's `version` field maps to leanpack's `sem_version`
- **dev mode**: Use `dev = true` with `dir = '~/projects/plugin-name'` for local development
- **optional**: Use `optional = true` for dependencies that won't block plugin loading
- **module trigger**: Use `module = "pattern"` for require()-based lazy loading

## Acknowledgements

- Inspired by [lazy.nvim](https://github.com/folke/lazy.nvim) for the declarative spec design

## License

MIT
