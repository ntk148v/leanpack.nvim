# parcel.nvim

A thin layer on top of Neovim's native `vim.pack`, adding support for lazy-loading and the widely adopted lazy.nvim-like declarative spec.

**Requirements:** Neovim 0.12+

## Why parcel?

Neovim 0.12+ includes a built-in plugin manager (`vim.pack`) that handles plugin installation, updates, and version management. parcel.nvim is a thin layer that adds:

- **Lazy-loading capabilities** - Load plugins on demand via events, commands, keymaps, or filetypes
- **lazy.nvim-compatible spec** - Use the same declarative spec you know and love
- **Build hooks** - Run commands on install/update
- **Dependency management** - Automatic dependency resolution and loading
- **Quick commands** - Simple plugin management commands

All while completely leveraging the native `vim.pack` infrastructure.

## Installation

```lua
-- Install with vim.pack directly
vim.pack.add({ 'https://github.com/ntk148v/parcel.nvim' })
```

## Quick Start

```lua
-- Set leader before loading parcel
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Setup with auto-import from lua/plugins/
require('parcel').setup()

-- Or with inline specs
require('parcel').setup({
  { 'neovim/nvim-lspconfig', config = function() ... end },
  { import = 'plugins' }, -- also import from lua/plugins/
})
```

## Directory Structure

Under the default setting, create plugin specs in `lua/plugins/`:

```
lua/
  plugins/
    treesitter.lua
    lsp.lua
    ...
```

Each file returns a spec or list of specs:

```lua
-- ./lua/plugins/treesitter.lua
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

## Spec Reference

```lua
{
  -- Plugin source (provide exactly one)
  [1] = "user/repo",                    -- Plugin short name. Expands to https://github.com/{user/repo}
  src = "https://...",                  -- Custom git URL or local path
  dir = "/path/to/plugin",              -- Local plugin directory (lazy.nvim compat)
  url = "https://...",                  -- Custom git URL (lazy.nvim compat)

  -- Dependencies
  dependencies = string|string[]|parcel.Spec|parcel.Spec[],

  -- Loading control
  enabled = true|false|function,        -- Enable/disable plugin
  cond = true|false|function(plugin),   -- Condition to load plugin
  lazy = true|false,                    -- Force eager loading when false
  priority = 50,                        -- Load priority (higher = earlier)

  -- Plugin configuration
  opts = {},                            -- Options passed to setup()
  init = function(plugin) end,          -- Runs before plugin loads
  config = function(plugin, opts) end,  -- Runs after plugin loads
  build = string|function(plugin),      -- Build command or function

  -- Lazy loading triggers
  event = string|string[]|table,         -- Load on event(s). Supports 'VeryLazy'
  cmd = string|string[],                -- Load on command(s)
  keys = string|table|table[],          -- Load on keymap(s)
  ft = string|string[],                 -- Load on filetype(s)

  -- Version control
  version = "main",                     -- Git branch, tag, or commit
  version = vim.version.range("1.*"),   -- Or semver range

  -- lazy.nvim compat
  sem_version = "^1.0.0",              -- Semver string (maps to version)
  branch = "main",                      -- Git branch
  tag = "v1.0.0",                       -- Git tag
  commit = "abc123",                    -- Git commit

  -- Plugin metadata
  name = "my-plugin",                   -- Custom plugin name
  main = "module.name",                -- Explicit main module
}
```

## Examples

### Basic Plugin

```lua
return {
  'nvim-mini/mini.bracketed',
  opts = {}, -- calls require('mini.bracketed').setup({})
}
```

### Lazy Load on Command

```lua
return {
  'nvim-tree/nvim-tree.lua',
  cmd = { 'NvimTreeToggle', 'NvimTreeFocus' },
  opts = {},
}
```

### Lazy Load on Keymap

```lua
return {
  'folke/flash.nvim',
  keys = {
    { 's', function() require('flash').jump() end, mode = { 'n', 'x', 'o' }, desc = 'Flash' },
    { 'S', function() require('flash').treesitter() end, mode = { 'n', 'x', 'o' }, desc = 'Flash Treesitter' },
  },
  opts = {},
}
```

### Lazy Load on Event

```lua
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  opts = {},
}
```

### Lazy Load on FileType

```lua
return {
  'rust-lang/rust.vim',
  ft = { 'rust', 'toml' },
}
```

### Build Hook

```lua
return {
  'nvim-telescope/telescope-fzf-native.nvim',
  build = 'make',
}
```

### Dependencies

```lua
return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-tree/nvim-web-devicons', opts = {} },
  },
}
```

### Version Pinning

```lua
return {
  'mrcjkb/rustaceanvim',
  version = vim.version.range('^6'), -- semver
  -- version = 'main', -- branch
  -- version = 'v1.0.0', -- tag
  -- version = 'abc123', -- commit
}
```

### Load Priority

```lua
return {
  'folke/tokyonight.nvim',
  priority = 1000, -- Load colorscheme early
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}
```

## Commands

parcel provides the following commands (default prefix: `P`, customizable via `cmd_prefix`):

- `:PUpdate [plugin]` - Update all plugins, or a specific plugin
- `:PClean` - Remove plugins that are no longer in your spec
- `:PBuild[!] [plugin]` - Run build hook for a specific plugin, or all plugins with `!`
- `:PLoad[!] [plugin]` - Load a specific unloaded plugin, or all unloaded plugins with `!`
- `:PDelete[!] [plugin]` - Remove a specific plugin, or all plugins with `!`
- `:PShow` - Open plugin manager UI

## UI

Open the plugin manager UI with `:PShow`.

Keymaps in the UI:
- `<Enter>/<CR>` - Load plugin under cursor
- `u` - Update plugin under cursor
- `b` - Build plugin under cursor
- `d` - Delete plugin under cursor
- `r` - Refresh plugin list
- `q/<Esc>` - Close UI

Status indicators:
- `●` - loaded
- `○` - pending
- `◐` - loading

## Configuration

```lua
require('parcel').setup({
  -- { import = 'plugins' }  -- default import spec if not explicitly passed
  defaults = {
    confirm = true,          -- set to false to skip vim.pack install prompts
    cond = nil,              -- global condition for all plugins
  },
  performance = {
    vim_loader = true,       -- enables vim.loader for faster startup
  },
  cmd_prefix = 'P',          -- command prefix: :PUpdate, :PClean, etc.
})
```

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with parcel. Key differences:

- **version pinning**: lazy.nvim's `version` field maps to parcel's `sem_version`
- **dev mode**: Use `src = vim.fn.expand('~/projects/my_plugin.nvim')` for local development
- **profiling**: Use `nvim --startuptime startuptime.log`

## Comparison with zpack.nvim

Both parcel.nvim and zpack.nvim are thin layers on top of `vim.pack`. Key differences:

| Feature | parcel.nvim | zpack.nvim |
|---------|-------------|------------|
| Module loader | ❌ | ✅ |
| Health check | ✅ | ❌ |
| Code size | ~800 LOC | ~1200 LOC |
| Architecture | Explicit state | Global state |

## Acknowledgements

- Inspired by [lazy.nvim](https://github.com/folke/lazy.nvim) for the declarative spec design
- Inspired by [zpack.nvim](https://github.com/zuqini/zpack.nvim) for the thin layer philosophy

## License

MIT
