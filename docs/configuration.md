# Configuration

leanpack.nvim is highly configurable. This guide covers all available options.

## Basic Configuration

```lua
require('leanpack').setup({
  -- Your plugin specs
  -- Can also be specified via { import = 'plugins' }
})
```

## Configuration Options

### `cmd_prefix`

- **Type**: `string`
- **Default**: `"Leanpack"`
- **Description**: Prefix for all leanpack commands

```lua
cmd_prefix = 'Leanpack',  -- Commands: :Leanpack update, :Leanpack clean, etc.
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
require('leanpack').setup({
  -- Command prefix
  cmd_prefix = 'leanpack',

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

leanpack.nvim looks for specs in multiple places:

1. **Passed directly** to `setup()`:

   ```lua
   require('leanpack').setup({
     { 'plugin1' },
     { 'plugin2' },
   })
   ```

2. **Import spec** - use `{ import = 'plugins' }`:

   ```lua
   require('leanpack').setup({
     { import = 'plugins' },  -- Loads from lua/plugins/
   })
   ```

3. **Default auto-import** - If no specs are passed, looks for `lua/plugins/`:
   ```lua
   require('leanpack').setup()  -- Auto-imports from lua/plugins/
   ```

## Environment Variables

leanpack.nvim respects standard Neovim paths:

- `stdpath("data")` - Plugin storage location
- `stdpath("log")` - Log file location (`leanpack.log`)

## Debug Mode

To enable debug logging:

1. Check the log file:

   ```lua
   -- View log location
   print(vim.fn.stdpath("log") .. "/leanpack.log")
   ```

2. Enable verbose logging (add to setup):
   ```lua
   -- Currently debug level is set via log.lua
   -- Check lua/leanpack/log.lua for options
   ```

## Next Steps

- [Plugin Spec](spec.md) - Define your plugins
- [Lazy Loading](lazy-loading.md) - Optimize startup
- [Commands](commands.md) - Available CLI commands
