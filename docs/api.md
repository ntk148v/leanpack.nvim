# API Reference

This document covers the Lua API for programmatic access to leanpack.nvim.

## Module Functions

### `leanpack.setup(opts)`

Initialize leanpack.nvim with configuration.

**Parameters:**

- `opts` (`table`): Configuration options

**Returns:** `nil`

```lua
require('leanpack').setup({
  cmd_prefix = 'leanpack',
  defaults = { confirm = true },
})
```

### `leanpack.set_profiling(enabled)`

Enable or disable startup profiling.

**Parameters:**

- `enabled` (`boolean`): Whether to enable profiling

**Returns:** `nil`

```lua
require('leanpack').set_profiling(true)
```

### `leanpack.get_profile_data()`

Get profiling results. Only meaningful after profiling has been enabled and `setup()` has run.

**Returns:** `table` with phase names as keys and elapsed milliseconds as values. Includes a `_total` key.

```lua
local profile = require('leanpack').get_profile_data()
-- { import_specs = 1.23, finalize_specs = 0.45, ..., _total = 12.34 }
```

## Plugin Management Commands

All plugin management operations are available as `:Leanpack` commands (not Lua API functions):

```vim
:Leanpack update              " Update all plugins
:Leanpack update plugin-name  " Update specific plugin
:Leanpack clean               " Remove unused plugins
:Leanpack sync                " Update + clean
:Leanpack fix                 " Detect and reinstall broken plugins
:Leanpack build!              " Run all build hooks
:Leanpack load!               " Load all pending plugins
:Leanpack profile             " View startup timing profile
```

See [Commands](commands.md) for full details.

## State Functions

### `leanpack.state.get_all_entries()`

Get all plugin entries.

**Returns:** `table` of plugin entries

```lua
local entries = require('leanpack.state').get_all_entries()
for src, entry in pairs(entries) do
  print(src, entry.load_status)
end
```

### `leanpack.state.get_entry(src)`

Get specific plugin entry.

**Parameters:**

- `src` (`string`): Plugin source

**Returns:** `table` or `nil`

```lua
local entry = require('leanpack.state').get_entry('nvim-treesitter/nvim-treesitter')
```

### `leanpack.state.is_configured()`

Check if leanpack is configured.

**Returns:** `boolean`

```lua
if require('leanpack.state').is_configured() then
  -- leanpack is ready
end
```

## Utility Functions

### `leanpack.spec.normalize_spec(spec)`

Normalize a plugin spec.

**Parameters:**

- `spec` (`table`): Plugin specification

**Returns:** `table` normalized spec

```lua
local normalized = require('leanpack.spec').normalize_spec({
  'user/repo',
  opts = {},
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
---@class leanpack.Plugin
---@field name string Plugin name
---@field path string Plugin directory path
---@field spec vim.pack.Spec The vim.pack spec
```

### Spec Table

```lua
---@class leanpack.Spec
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
