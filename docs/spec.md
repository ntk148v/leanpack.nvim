# Plugin Spec Reference

This document details all available options when defining plugin specifications.

## Basic Syntax

### Short Name

```lua
{ 'user/repo' }  -- Expands to https://github.com/user/repo
```

### Full URL

```lua
{ src = 'https://github.com/user/repo' }
```

### Local Path

```lua
{ src = '/path/to/local/plugin' }
```

## Plugin Source Fields

| Field  | Type     | Description                        |
| ------ | -------- | ---------------------------------- |
| `[1]`  | `string` | Short name (user/repo)             |
| `src`  | `string` | Source URL or local path           |
| `dir`  | `string` | Local directory (lazy.nvim compat) |
| `url`  | `string` | Git URL (lazy.nvim compat)         |
| `name` | `string` | Custom plugin name                 |

## Version Control

| Field         | Type     | Description                            |
| ------------- | -------- | -------------------------------------- |
| `version`     | `string` | Branch, tag, or commit                 |
| `version`     | `Range`  | Semver range via `vim.version.range()` |
| `sem_version` | `string` | Semver (lazy.nvim compat)              |
| `branch`      | `string` | Git branch                             |
| `tag`         | `string` | Git tag                                |
| `commit`      | `string` | Git commit hash                        |

### Version Examples

```lua
{ 'user/repo', version = 'main' }              -- Branch
{ 'user/repo', version = 'v1.0.0' }           -- Tag
{ 'user/repo', version = 'abc123' }            -- Commit
{ 'user/repo', version = vim.version.range('^1.0') }  -- Semver

-- lazy.nvim compatibility
{ 'user/repo', sem_version = '^1.0.0' }
{ 'user/repo', branch = 'main' }
{ 'user/repo', tag = 'v1.0.0' }
{ 'user/repo', commit = 'abc123' }
```

## Dependencies

| Field          | Type                            | Description              |
| -------------- | ------------------------------- | ------------------------ |
| `dependencies` | `string\|string[]\|Spec\|table` | Plugin dependencies      |
| `optional`     | `boolean`                       | Optional dependency flag |

### Dependencies Syntax

```lua
-- Simple string
{ 'user/repo', dependencies = 'dep/plugin' }

-- String array
{ 'user/repo', dependencies = { 'dep1', 'dep2' } }

-- lazy.nvim multi-string format
{ 'user/repo', dependencies = { 'dep1', { 'dep2', 'dep3' } } }

-- Full specs
{ 'user/repo', dependencies = {
  { 'dep/plugin', opts = {} },
} }

-- Optional dependency
{ 'user/repo', dependencies = {
  { 'optional/dep', optional = true },
} }
```

## Loading Control

| Field      | Type                | Description                      |
| ---------- | ------------------- | -------------------------------- |
| `enabled`  | `boolean\|function` | Enable/disable plugin            |
| `cond`     | `boolean\|function` | Conditional loading              |
| `lazy`     | `boolean`           | Force lazy loading               |
| `priority` | `number`            | Load priority (higher = earlier) |

### Loading Examples

```lua
-- Enable based on condition
{ 'user/repo', enabled = vim.fn.has('linux') == 1 }

-- Conditional loading
{ 'user/repo', cond = function()
  return vim.fn.filereadable('.project') == 1
end }

-- Force eager loading
{ 'user/repo', lazy = false }

-- Load priority (higher loads first)
{ 'user/repo', priority = 100 }
```

## Development Mode

| Field | Type      | Description       |
| ----- | --------- | ----------------- |
| `dev` | `boolean` | Enable dev mode   |
| `dir` | `string`  | Local plugin path |

### Dev Mode Example

```lua
{ 'user/repo', dev = true, dir = '~/projects/plugin-name' }
```

## Lazy Loading Triggers

### Event Trigger

| Field   | Type                      | Description   |
| ------- | ------------------------- | ------------- |
| `event` | `string\|string[]\|table` | Neovim events |

```lua
{ 'user/repo', event = 'InsertEnter' }
{ 'user/repo', event = { 'InsertEnter', 'CmdlineEnter' } }
{ 'user/repo', event = 'BufReadPre *.lua' }
{ 'user/repo', event = 'VeryLazy' }  -- After UIEnter
```

### Pattern Option

For `event`, you can specify a fallback pattern:

| Field     | Type     | Description                             |
| --------- | -------- | --------------------------------------- |
| `pattern` | `string` | Fallback autocmd pattern (default: `*`) |

```lua
{ 'user/repo', event = 'BufReadPre', pattern = '*.lua' }
```

### Command Trigger

| Field | Type               | Description   |
| ----- | ------------------ | ------------- |
| `cmd` | `string\|string[]` | User commands |

```lua
{ 'user/repo', cmd = 'MyCommand' }
{ 'user/repo', cmd = { 'Cmd1', 'Cmd2' } }
```

### Keymap Trigger

| Field  | Type                     | Description |
| ------ | ------------------------ | ----------- |
| `keys` | `string\|table\|table[]` | Keymaps     |

```lua
-- Simple key
{ 'user/repo', keys = '<leader>f' }

-- With options
{ 'user/repo', keys = {
  { '<leader>f', function() require('plugin').action() end, desc = 'Action' },
  { '<leader>g', '<cmd>PluginCmd<cr>', mode = 'n', desc = 'Command' },
} }
```

### Filetype Trigger

| Field | Type               | Description |
| ----- | ------------------ | ----------- |
| `ft`  | `string\|string[]` | File types  |

```lua
{ 'user/repo', ft = 'lua' }
{ 'user/repo', ft = { 'lua', 'vim' } }
```

## Hooks

| Field    | Type                | Description              |
| -------- | ------------------- | ------------------------ |
| `init`   | `function`          | Runs before plugin loads |
| `config` | `function\|boolean` | Runs after plugin loads  |
| `build`  | `string\|function`  | Runs on install/update   |
| `opts`   | `table`             | Auto-setup options       |

### Hook Examples

```lua
-- Init hook (runs before load)
{ 'user/repo', init = function()
  vim.g.some_setting = true
end }

-- Config function
{ 'user/repo', config = function()
  require('plugin').setup({ option = 'value' })
end }

-- Auto-setup with opts
{ 'user/repo', opts = { option = 'value' } }

-- Build hook (string)
{ 'user/repo', build = 'make' }

-- Build hook (function)
{ 'user/repo', build = function()
  vim.fn.system({ 'make', '-C', plugin.path })
end }
```

## Plugin Metadata

| Field  | Type     | Description                                     |
| ------ | -------- | ----------------------------------------------- |
| `name` | `string` | Custom plugin name                              |
| `main` | `string` | Explicit main module (auto-detected if omitted) |

```lua
{ 'user/repo', name = 'my-plugin' }
{ 'user/repo', main = 'plugin.main' }  -- Explicit main module
```

### Automatic Main Module Detection

When using `opts` or `config = true` without specifying a `main` field, leanpack will automatically detect the main module by:

1. Scanning the plugin's `lua/` directory for module folders
2. Matching the plugin name against folder names (using normalization like lazy.nvim)
3. Looking for `init.lua` files in matched folders

**Example:** For `nvimtools/none-ls.nvim`, leanpack auto-detects `null-ls` as the main module (since the internal folder is named `null-ls`), allowing you to use:

```lua
{
  'nvimtools/none-ls.nvim',
  opts = { sources = {} }  -- No main field needed!
}
```

This matches lazy.nvim's behavior where plugins work out of the box without manual configuration.

## Complete Example

```lua
return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-tree/nvim-web-devicons', opts = {} },
  },
  opts = {
    defaults = {
      prompt_prefix = ' ',
    },
  },
  config = function()
    local telescope = require('telescope')
    telescope.setup(vim.tbl_deep_extend('force', telescope.loaded().telescope.opts, {
      defaults = {
        mappings = {
          n = { ['<c-t>'] = require('telescope._actions').select_tab },
        },
      },
    }))
  end,
}
```

## Next Steps

- [Lazy Loading](lazy-loading.md) - Deep dive into lazy loading
- [Getting Started](getting-started.md) - Quick start guide
