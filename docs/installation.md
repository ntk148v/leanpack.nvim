# Installation

parcel.nvim offers multiple installation methods. Choose the one that best fits your workflow.

## Requirements

- Neovim 0.12.0 or later
- Git (required by vim.pack)

## Methods

### 1. Bootstrap (Recommended)

This is the recommended method for most users. Add this to the top of your `init.lua`:

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

-- Now you can require parcel
require("parcel").setup({
  -- your config here
})
```

This method:

- Automatically installs parcel.nvim if not present
- Works on fresh systems without manual setup
- Can be combined with other bootstrap managers

### 2. Manual Installation with vim.pack

If you already have Neovim set up:

```lua
-- Install with vim.pack directly
vim.pack.add({ 'ntk148v/parcel.nvim' })

-- Then setup in your init.lua
require("parcel").setup()
```

### 3. Using a Package Manager

#### Using packer.nvim

```lua
use 'ntk148v/parcel.nvim'
```

#### Using lazy.nvim

```lua
{ 'ntk148v/parcel.nvim' }
```

#### Using vim-plug

```vim
Plug 'ntk148v/parcel.nvim'
```

## Directory Structure

After installation, parcel.nvim will manage plugins in:

```
~/.local/share/nvim/
└── site/
    ├── pack/
    │   ├── parcel/
    │   │   ├── opt/
    │   │   │   └── parcel.nvim/  (parcel.nvim itself)
    │   │   └── start/
    │   │       └── ...           (eager-loaded plugins)
    │   └── nvim-pack/            (managed plugins)
    │       ├── opt/              (lazy plugins)
    │       └── start/            (eager plugins)
    └── lua/
        └── plugin/               (compiled Lua)
```

## Updating parcel.nvim

To update parcel.nvim itself:

```vim
:Parcel update parcel.nvim
```

Or via Lua:

```lua
vim.pack.add({ 'ntk148v/parcel.nvim', update = true })
```

## Uninstalling

To uninstall parcel.nvim:

```bash
rm -rf ~/.local/share/nvim/site/pack/parcel/opt/parcel.nvim
```

Note: This will not remove your other plugins. To clean those, use `:Parcel clean`.

## Next Steps

- [Getting Started](getting-started.md) - Quick setup guide
- [Configuration](configuration.md) - Customize your setup
