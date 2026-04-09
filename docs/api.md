# API Reference

This document covers the Lua API for programmatic access to parcel.nvim.

## Module Functions

### `parcel.setup(opts)`

Initialize parcel.nvim with configuration.

**Parameters:**

- `opts` (`table`): Configuration options

**Returns:** `nil`

```lua
require('parcel').setup({
  cmd_prefix = 'Parcel',
  defaults = { confirm = true },
})
```

### `parcel.update([plugin])`

Update plugins.

**Parameters:**

- `plugin` (`string`, optional): Specific plugin to update

**Returns:** `nil`

```lua
-- Update all
require('parcel').update()

-- Update specific
require('parcel').update('nvim-lspconfig')
```

### `parcel.build([plugin])`

Run build hooks for plugins.

**Parameters:**

- `plugin` (`string`, optional): Specific plugin to build

**Returns:** `nil`

```lua
-- Build all
require('parcel').build()

-- Build specific
require('parcel').build('telescope-fzf-native')
```

### `parcel.load([plugin])`

Load lazy plugins.

**Parameters:**

- `plugin` (`string`, optional): Specific plugin to load

**Returns:** `nil`

```lua
-- Load all pending
require('parcel').load()

-- Load specific
require('parcel').load('nvim-tree')
```

### `parcel.clean()`

Remove plugins not in spec.

**Returns:** `nil`

```lua
require('parcel').clean()
```

### `parcel.status()`

Get plugin status summary.

**Returns:** `table` with plugin counts

```lua
local status = require('parcel').status()
-- { loaded = 10, pending = 5, total = 15 }
```

## State Functions

### `parcel.state.get_all_entries()`

Get all plugin entries.

**Returns:** `table` of plugin entries

```lua
local entries = require('parcel.state').get_all_entries()
for src, entry in pairs(entries) do
  print(src, entry.load_status)
end
```

### `parcel.state.get_entry(src)`

Get specific plugin entry.

**Parameters:**

- `src` (`string`): Plugin source

**Returns:** `table` or `nil`

```lua
local entry = require('parcel.state').get_entry('nvim-treesitter/nvim-treesitter')
```

### `parcel.state.is_configured()`

Check if parcel is configured.

**Returns:** `boolean`

```lua
if require('parcel.state').is_configured() then
  -- Parcel is ready
end
```

## Utility Functions

### `parcel.spec.normalize_spec(spec)`

Normalize a plugin spec.

**Parameters:**

- `spec` (`table`): Plugin specification

**Returns:** `table` normalized spec

```lua
local normalized = require('parcel.spec').normalize_spec({
  'user/repo',
  opts = {},
})
```

### `parcel.spec.detect_main(plugin)`

Detect main module for a plugin.

**Parameters:**

- `plugin` (`vim.pack.Plugin`): Plugin object

**Returns:** `string` or `nil`

```lua
local main = require('parcel.spec').detect_main(plugin)
```

## Events

parcel.nvim uses Neovim autocommands. You can hook into these:

### `ParcelInstalled`

Fires after a plugin is installed.

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'ParcelInstalled',
  callback = function(args)
    local plugin = args.data.plugin
    print('Installed: ' .. plugin.name)
  end,
})
```

### `ParcelUpdated`

Fires after a plugin is updated.

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'ParcelUpdated',
  callback = function(args)
    local plugin = args.data.plugin
    print('Updated: ' .. plugin.name)
  end,
})
```

### `ParcelLoaded`

Fires after a plugin is loaded.

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'ParcelLoaded',
  callback = function(args)
    local plugin = args.data.plugin
    print('Loaded: ' .. plugin.name)
  end,
})
```

## Hooks

Plugins can define hooks in their specs:

### `init(plugin)`

Runs before plugin loads.

```lua
return {
  'user/repo',
  init = function(plugin)
    vim.g.plugin_loaded = true
  end,
}
```

### `config(plugin, opts)`

Runs after plugin loads.

```lua
return {
  'user/repo',
  config = function(plugin, opts)
    require('plugin').setup(opts)
  end,
}
```

### `build(plugin)`

Runs on install/update.

```lua
return {
  'user/repo',
  build = function(plugin)
    vim.fn.system({ 'make', '-C', plugin.path })
  end,
}
```

## Types

### Plugin Object

```lua
---@class parcel.Plugin
---@field name string Plugin name
---@field path string Plugin directory path
---@field spec vim.pack.Spec The vim.pack spec
```

### Spec Table

```lua
---@class parcel.Spec
---@field [1] string Short name (user/repo)
---@field src? string Source URL or path
---@field dir? string Local directory
---@field url? string Git URL
---@field name? string Custom name
---@field dependencies? string|string[]|table Dependencies
---@field optional? boolean Optional dependency
---@field enabled? boolean|function Enable/disable
---@field cond? boolean|function Conditional loading
---@field lazy? boolean Force lazy loading
---@field priority? number Load priority
---@field dev? boolean Dev mode
---@field opts? table Setup options
---@field init? function Init hook
---@field config? function|boolean Config hook
---@field build? string|function Build hook
---@field event? string|string[]|table Event trigger
---@field cmd? string|string[] Command trigger
---@field keys? string|table|table[] Keymap trigger
---@field ft? string|string[] Filetype trigger
---@field version? string Version
---@field sem_version? string Semver (lazy.nvim compat)
---@field branch? string Branch
---@field tag? string Tag
---@field commit? string Commit
---@field main? string Main module
```

## Next Steps

- [Commands](commands.md) - CLI reference
- [Troubleshooting](troubleshooting.md) - Common issues
