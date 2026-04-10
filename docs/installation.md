# Installation

leanpack.nvim offers multiple installation methods. Choose the one that best fits your workflow.

## Requirements

- Neovim 0.12.0 or later
- Git (required by vim.pack)

## Methods

### 1. Bootstrap (Recommended)

This is the recommended method for most users. Add this to the top of your `init.lua`:

```lua
-- Bootstrap leanpack.nvim
local lazypath = vim.fn.stdpath("data") .. "/site/pack/leanpack/opt/leanpack.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/ntk148v/leanpack.nvim",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Now you can require leanpack
require("leanpack").setup({
  -- your config here
})
```

This method:

- Automatically installs leanpack.nvim if not present
- Works on fresh systems without manual setup
- Can be combined with other bootstrap managers

### 2. Manual Installation with vim.pack

If you already have Neovim set up:

```lua
-- Install with vim.pack directly
vim.pack.add({ 'ntk148v/leanpack.nvim' })

-- Then setup in your init.lua
require("leanpack").setup()
```

### 3. Using a Package Manager

#### Using packer.nvim

```lua
use 'ntk148v/leanpack.nvim'
```

#### Using lazy.nvim

```lua
{ 'ntk148v/leanpack.nvim' }
```

#### Using vim-plug

```vim
Plug 'ntk148v/leanpack.nvim'
```

## Directory Structure

After installation, leanpack.nvim will manage plugins in:

```
~/.local/share/nvim/
└── site/
    ├── pack/
    │   ├── leanpack/
    │   │   ├── opt/
    │   │   │   └── leanpack.nvim/  (leanpack.nvim itself)
    │   │   └── start/
    │   │       └── ...           (eager-loaded plugins)
    │   └── nvim-pack/            (managed plugins)
    │       ├── opt/              (lazy plugins)
    │       └── start/            (eager plugins)
    └── lua/
        └── plugin/               (compiled Lua)
```

## Updating leanpack.nvim

To update leanpack.nvim itself:

```vim
:Leanpack update leanpack.nvim
```

Or via Lua:

```lua
vim.pack.add({ 'ntk148v/leanpack.nvim', update = true })
```

## Uninstalling

To uninstall leanpack.nvim:

```bash
rm -rf ~/.local/share/nvim/site/pack/leanpack/opt/leanpack.nvim
```

Note: This will not remove your other plugins. To clean those, use `:Leanpack clean`.

## Next Steps

- [Getting Started](getting-started.md) - Quick setup guide
- [Configuration](configuration.md) - Customize your setup
