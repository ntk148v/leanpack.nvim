# Migration Guides

This section covers migrating from other plugin managers to leanpack.nvim.

## From lazy.nvim

Most lazy.nvim specs work directly with leanpack.nvim.

### Key Differences

| lazy.nvim          | leanpack.nvim       | Notes                              |
| ------------------ | ------------------- | ---------------------------------- |
| `version` (semver) | `sem_version`       | `version` is for branch/tag/commit |
| `module` trigger   | Not supported       | Uses explicit dependencies instead |
| Profiling UI       | Use `--startuptime` | Built-in Neovim flag               |

### Example Migration

**lazy.nvim:**

```lua
{
  'folke/tokyonight.nvim',
  version = '^2.0',
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}
```

**leanpack.nvim:**

```lua
{
  'folke/tokyonight.nvim',
  sem_version = '^2.0',  -- or version = vim.version.range('^2.0')
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}
```

### Migrating `module` Trigger

lazy.nvim uses `package.loaders` interception for module-based loading. leanpack.nvim doesn't support this for performance reasons.

Instead, use explicit dependencies:

**lazy.nvim:**

```lua
{
  'neovim/nvim-lspconfig',
  module = 'lspconfig',
}
```

**leanpack.nvim:**

```lua
{
  'neovim/nvim-lspconfig',
  -- No module trigger needed
  -- Just ensure lspconfig is in your dependencies where needed
}
```

Or load on first require:

```lua
-- In your config
vim.api.nvim_create_autocmd('FileType', {
  pattern = '*',
  once = true,
  callback = function()
    require('lspconfig')
  end,
})
```

### Migrating Plugin Specs

1. Copy your plugin specs to `lua/plugins/`
2. Update `version` to `sem_version` for semver ranges
3. Remove `module` triggers (use explicit deps instead)
4. Test with `:Leanpack update`

### Common Mappings

| lazy.nvim             | leanpack.nvim             |
| --------------------- | ------------------------- |
| `version = '^1.0'`    | `sem_version = '^1.0'`    |
| `version = 'main'`    | `version = 'main'`        |
| `module = 'pattern'`  | Remove (use dependencies) |
| `lazy = true`         | Keep as-is                |
| `init = function()`   | Keep as-is                |
| `config = function()` | Keep as-is                |

## From packer.nvim

### Key Differences

| packer.nvim      | leanpack.nvim                |
| ---------------- | ---------------------------- |
| Async by default | Uses vim.pack (native async) |
| Custom lockfile  | Uses nvim-pack-lock.json     |
| `use` function   | Direct table specs           |

### Example Migration

**packer.nvim:**

```lua
return require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  use 'neovim/nvim-lspconfig'
  use {
    'nvim-telescope/telescope.nvim',
    requires = { 'nvim-lua/plenary.nvim' },
  }
end)
```

**leanpack.nvim:**

Create `lua/plugins/init.lua`:

```lua
return {
  'wbthomason/packer.nvim',
  'neovim/nvim-lspconfig',
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
  },
}
```

Then in `init.lua`:

```lua
require('leanpack').setup({ import = 'plugins' })
```

### Convert Automatically

You can use a conversion script to transform packer specs:

```bash
# Manual conversion: copy specs to lua/plugins/
```

## From vim-plug

### Key Differences

| vim-plug          | leanpack.nvim                 |
| ----------------- | ----------------------------- |
| `Plugin` function | Direct table specs            |
| `Plug` command    | `require('leanpack').setup()` |
| Manual install    | Auto-install via vim.pack     |

### Example Migration

**vim-plug:**

```vim
call plug#begin('~/.local/share/nvim/plugged')
Plug 'neovim/nvim-lspconfig'
Plug 'nvim-treesitter/nvim-treesitter', { 'for': ['lua', 'vim'] }
call plug#end()
```

**leanpack.nvim:**

```lua
-- lua/plugins/init.lua
return {
  'neovim/nvim-lspconfig',
  {
    'nvim-treesitter/nvim-treesitter',
    ft = { 'lua', 'vim' },
  },
}
```

## From mini.deps

### Key Differences

| mini.deps           | leanpack.nvim              |
| ------------------- | -------------------------- |
| `add()` function    | Declarative specs          |
| `now()` / `later()` | Lazy triggers              |
| Manual deps         | Auto-dependency resolution |

### Example Migration

**mini.deps:**

```lua
require('mini.deps').add({ source = 'neovim/nvim-lspconfig' })
require('mini.deps').add({ source = 'nvim-treesitter/nvim-treesitter' })
```

**leanpack.nvim:**

```lua
-- lua/plugins/lsp.lua
return 'neovim/nvim-lspconfig'

-- lua/plugins/treesitter.lua
return 'nvim-treesitter/nvim-treesitter'
```

## General Tips

### 1. Organize Plugins by Feature

```
lua/
└── plugins/
    ├── init.lua        -- Packer/misc plugins
    ├── treesitter.lua  -- Treesitter
    ├── lsp.lua         -- LSP config
    └── ui.lua          -- UI plugins
```

### 2. Use Dependencies

Always declare dependencies explicitly:

```lua
{
  'nvim-telescope/telescope.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
}
```

### 3. Test Incrementally

1. Start with essential plugins
2. Add lazy loading triggers
3. Test with `:Leanpack update`
4. Verify with `:checkhealth leanpack`

## Next Steps

- [Getting Started](getting-started.md) - Quick start
- [Configuration](configuration.md) - Full config options
