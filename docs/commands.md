# Commands

parcel.nvim provides a unified command interface for plugin management.

## Command Prefix

By default, all commands are prefixed with `Parcel`. This can be customized in setup:

```lua
require('parcel').setup({
  cmd_prefix = 'MyPrefix',  -- Commands: MyPrefix update, etc.
})
```

## Available Commands

### `:Parcel`

Open the plugin manager UI.

```vim
:Parcel
```

### `:Parcel update` [plugin]

Update all plugins, or a specific plugin.

```vim
:Parcel update              " Update all
:Parcel update nvim-lspconfig  " Update specific
```

With tab completion for plugin names.

### `:Parcel clean`

Remove plugins that are no longer in your spec.

```vim
:Parcel clean
```

### `:Parcel build[!]` [plugin]

Run the build hook for a plugin.

```vim
:Parcel build telescope  " Build specific plugin
:Parcel build!         " Build all plugins with build hooks
```

### `:Parcel load[!]` [plugin]

Load an unloaded plugin.

```vim
:Parcel load nvim-tree  " Load specific plugin
:Parcel load!          " Load all unloaded plugins
```

### `:Parcel delete[!]` [plugin]

Remove a plugin from the filesystem.

```vim
:Parcel delete telescope  " Delete specific plugin
:Parcel delete!           " Delete all managed plugins
```

## UI Commands

### `:Parcel`

Opens a floating window with:

- List of all managed plugins
- Status (loaded/pending/loading)
- Dependencies
- Build information

### Keymaps in UI

| Key       | Action                     |
| --------- | -------------------------- |
| `<Enter>` | Load plugin under cursor   |
| `u`       | Update plugin under cursor |
| `b`       | Build plugin under cursor  |
| `d`       | Delete plugin under cursor |
| `r`       | Refresh plugin list        |
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
require('parcel').update()              -- Update all
require('parcel').update('plugin-name') -- Update specific
```

### Build Plugins

```lua
require('parcel').build()                -- Build all
require('parcel').build('plugin-name')  -- Build specific
```

### Load Plugins

```lua
require('parcel').load()                 -- Load all pending
require('parcel').load('plugin-name')    -- Load specific
```

### Clean Plugins

```lua
require('parcel').clean()
```

## Health Check

### `:checkhealth parcel`

Run health checks to verify installation:

```vim
:checkhealth parcel
```

Checks:

- Neovim version (0.12+ required)
- vim.pack availability
- Git availability
- Unloaded plugins
- Pending build hooks
- Lockfile status

## Tab Completion

All parcel commands support tab completion:

```vim
:Parcel update <Tab>    " Complete plugin names
:Parcel build <Tab>     " Complete plugin names
:Parcel delete <Tab>    " Complete plugin names
```

## Output

Commands output to:

- Neovim command line (for simple messages)
- Floating UI (for progress during long operations)
- Log file (for debugging)

Log location: `vim.fn.stdpath("log") .. "/parcel.log"`

## Next Steps

- [API](api.md) - Complete Lua API reference
- [Troubleshooting](troubleshooting.md) - Common issues
