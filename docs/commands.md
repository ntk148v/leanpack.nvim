# Commands

leanpack.nvim provides a unified command interface for plugin management.

## Command Prefix

By default, all commands are prefixed with `leanpack`. This can be customized in setup:

```lua
require('leanpack').setup({
  cmd_prefix = 'MyPrefix',  -- Commands: MyPrefix update, etc.
})
```

## Available Commands

### `:Leanpack`

Open the plugin manager UI.

```vim
:Leanpack
```

### `:Leanpack update` [plugin]

Update all plugins, or a specific plugin.

```vim
:Leanpack update              " Update all
:Leanpack update nvim-lspconfig  " Update specific
```

With tab completion for plugin names.

### `:Leanpack clean`

Remove plugins that are no longer in your spec.

```vim
:Leanpack clean
```

### `:Leanpack build[!]` [plugin]

Run the build hook for a plugin.

```vim
:Leanpack build telescope  " Build specific plugin
:Leanpack build!         " Build all plugins with build hooks
```

### `:Leanpack load[!]` [plugin]

Load an unloaded plugin.

```vim
:Leanpack load nvim-tree  " Load specific plugin
:Leanpack load!          " Load all unloaded plugins
```

### `:Leanpack delete[!]` [plugin]

Remove a plugin from the filesystem.

```vim
:Leanpack delete telescope  " Delete specific plugin
:Leanpack delete!           " Delete all managed plugins
```

### `:Leanpack sync`

Synchronize all plugins. This is a shortcut for `update` followed by `clean`.

```vim
:Leanpack sync
```

### `:Leanpack profile`

Show detailed internal startup timing profile for `leanpack.nvim`.

```vim
:Leanpack profile
```

## UI Commands

### `:Leanpack`

Opens a floating window with:

- List of all managed plugins with search filtering
- Status (loaded/pending/loading)
- Dependencies
- Build information

### Keymaps in UI

| Key       | Action                     |
| --------- | -------------------------- |
| `<Enter>` | Load plugin under cursor   |
| `u`       | Update plugin under cursor |
| `U`       | Update all plugins         |
| `<C-u>`   | Update all loaded plugins  |
| `b`       | Build plugin under cursor  |
| `d`       | Delete plugin under cursor |
| `r`       | Refresh plugin list        |
| `/`       | Search/filter plugins      |
| `<C-c>`   | Clear search filter        |
| `q`       | Close UI                   |
| `<Esc>`   | Close UI                   |

### Status Indicators

- `●` - Plugin is loaded
- `○` - Plugin is pending (lazy)
- `◐` - Plugin is currently loading

## Lua API

Commands can also be called from Lua:

### Update Plugins

```lua
require('leanpack').update()              -- Update all
require('leanpack').update('plugin-name') -- Update specific
```

### Build Plugins

```lua
require('leanpack').build()                -- Build all
require('leanpack').build('plugin-name')  -- Build specific
```

### Load Plugins

```lua
require('leanpack').load()                 -- Load all pending
require('leanpack').load('plugin-name')    -- Load specific
```

### Clean Plugins

```lua
require('leanpack').clean()
```

## Health Check

### `:checkhealth leanpack`

Run health checks to verify installation:

```vim
:checkhealth leanpack
```

Checks:

- Neovim version (0.12+ required)
- vim.pack availability
- Git availability
- Unloaded plugins
- Pending build hooks
- Lockfile status

## Tab Completion

All leanpack commands support tab completion:

```vim
:Leanpack update <Tab>    " Complete plugin names
:Leanpack build <Tab>     " Complete plugin names
:Leanpack delete <Tab>    " Complete plugin names
```

## Output

Commands output to:

- Neovim command line (for simple messages)
- Floating UI (for progress during long operations)
- Log file (for debugging)

Log location: `vim.fn.stdpath("log") .. "/leanpack.log"`

## Next Steps

- [API](api.md) - Complete Lua API reference
- [Troubleshooting](troubleshooting.md) - Common issues
