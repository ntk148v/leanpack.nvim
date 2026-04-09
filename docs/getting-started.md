# Getting Started with parcel.nvim

This guide will help you get parcel.nvim up and running in under 5 minutes.

## Prerequisites

- Neovim 0.12.0 or later
- Git (required by vim.pack for cloning repositories)

## Step 1: Bootstrap parcel.nvim

Add this to the top of your `init.lua`:

```lua
-- Bootstrap parcel.nvim
local lazypath = vim.fn.stdpath("data") .. "/site/pack/parcel/opt/parcel.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/ntk148v/parcel.nvim",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)
```

## Step 2: Set Up Your Leader Keys

Set your leader keys before loading parcel (recommended):

```lua
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
```

## Step 3: Initialize parcel.nvim

Add to your `init.lua` (after the bootstrap):

```lua
require("parcel").setup()
```

By default, parcel.nvim will look for plugin specs in `lua/plugins/`.

## Step 4: Create Plugin Specs

Create a `lua/plugins/` directory in your config:

```
~/.config/nvim/
└── lua/
    └── plugins/
        ├── treesitter.lua
        ├── lsp.lua
        └── ...
```

Each file returns a plugin spec:

```lua
-- lua/plugins/treesitter.lua
return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter.configs').setup({
      highlight = { enable = true },
    })
  end,
}
```

## Step 5: Restart Neovim

Restart Neovim and parcel.nvim will:

1. Automatically install all plugins from `lua/plugins/`
2. Set up lazy loading triggers
3. Create the `:Parcel` command

## Verify Installation

Open Neovim and run:

```vim
:checkhealth parcel
```

You should see:

- Neovim 0.12+ detected
- vim.pack module available
- Git available

## Quick Test Commands

| Command          | Description            |
| ---------------- | ---------------------- |
| `:Parcel`        | Open plugin manager UI |
| `:Parcel update` | Update all plugins     |
| `:Parcel build!` | Run all build hooks    |

## What's Next?

- [Configuration Guide](configuration.md) - Customize parcel.nvim
- [Plugin Spec Reference](spec.md) - Learn all spec options
- [Lazy Loading Guide](lazy-loading.md) - Optimize startup time
- [Migrating from lazy.nvim](migrating.md) - If you're coming from lazy.nvim

## Troubleshooting

If plugins don't load:

1. Check `:checkhealth parcel`
2. Run `:Parcel update` to install plugins
3. Check logs at `vim.fn.stdpath("log") .. "/parcel.log"`

For more help, see [Troubleshooting](troubleshooting.md).
