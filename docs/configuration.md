# Configuration

parcel.nvim is highly configurable. This guide covers all available options.

## Basic Configuration

```lua
require('parcel').setup({
  -- Your plugin specs
  -- Can also be specified via { import = 'plugins' }
})
```

## Configuration Options

### `cmd_prefix`

- **Type**: `string`
- **Default**: `"Parcel"`
- **Description**: Prefix for all parcel commands

```lua
cmd_prefix = 'Parcel',  -- Commands: :Parcel update, :Parcel clean, etc.
```

### `defaults`

- **Type**: `table`
- **Default**: `{}`
- **Description**: Default options applied to all plugins

```lua
defaults = {
  confirm = true,   -- Ask for confirmation on install/update
  cond = nil,       -- Global condition function for all plugins
}
```

### `performance`

- **Type**: `table`
- **Default**: `{}`
- **Description**: Performance-related options

```lua
performance = {
  vim_loader = true,  -- Enable vim.loader for faster startup
}
```

### `git`

- **Type**: `table`
- **Default**: `{}`
- **Description**: Git operation settings

```lua
git = {
  throttle = {
    requests = 10,    -- Max concurrent git operations
    interval = 1000,  -- Interval in ms between requests
  },
}
```

## Full Configuration Example

```lua
require('parcel').setup({
  -- Command prefix
  cmd_prefix = 'Parcel',

  -- Default options for all plugins
  defaults = {
    confirm = true,   -- Ask for confirmation
    cond = nil,       -- No global condition
  },

  -- Performance tuning
  performance = {
    vim_loader = true,  -- Enable vim.loader
  },

  -- Git throttling to prevent rate limits
  git = {
    throttle = {
      requests = 10,
      interval = 1000,
    },
  },
})
```

## Configuration Loading

parcel.nvim looks for specs in multiple places:

1. **Passed directly** to `setup()`:

   ```lua
   require('parcel').setup({
     { 'plugin1' },
     { 'plugin2' },
   })
   ```

2. **Import spec** - use `{ import = 'plugins' }`:

   ```lua
   require('parcel').setup({
     { import = 'plugins' },  -- Loads from lua/plugins/
   })
   ```

3. **Default auto-import** - If no specs are passed, looks for `lua/plugins/`:
   ```lua
   require('parcel').setup()  -- Auto-imports from lua/plugins/
   ```

## Environment Variables

parcel.nvim respects standard Neovim paths:

- `stdpath("data")` - Plugin storage location
- `stdpath("log")` - Log file location (`parcel.log`)

## Debug Mode

To enable debug logging:

1. Check the log file:

   ```lua
   -- View log location
   print(vim.fn.stdpath("log") .. "/parcel.log")
   ```

2. Enable verbose logging (add to setup):
   ```lua
   -- Currently debug level is set via log.lua
   -- Check lua/parcel/log.lua for options
   ```

## Next Steps

- [Plugin Spec](spec.md) - Define your plugins
- [Lazy Loading](lazy-loading.md) - Optimize startup
- [Commands](commands.md) - Available CLI commands
