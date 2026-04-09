# Lazy Loading

parcel.nvim provides multiple lazy loading mechanisms to optimize Neovim startup time.

## Overview

Lazy loading defers plugin activation until needed. This reduces startup time by only loading plugins when you use their features.

parcel.nvim implements four lazy loading trigger types:

1. **Event** - Load when a Neovim event fires
2. **Command** - Load when a user command is called
3. **Keymap** - Load when a key is pressed
4. **Filetype** - Load when a file type is detected

## Event Trigger

Load a plugin when a Neovim event occurs.

### Syntax

```lua
return {
  'plugin/name',
  event = 'EventName',
}
```

### Common Events

| Event          | Description                              |
| -------------- | ---------------------------------------- |
| `VeryLazy`     | After UIEnter (default for lazy plugins) |
| `BufReadPre`   | Before reading a buffer                  |
| `BufReadPost`  | After reading a buffer                   |
| `BufNew`       | For new buffers                          |
| `TabEnter`     | When switching tabs                      |
| `InsertEnter`  | When entering insert mode                |
| `CmdlineEnter` | When entering command line               |

### Examples

```lua
-- Load on InsertEnter event
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  opts = {},
}

-- Load on multiple events
return {
  'user/plugin',
  event = { 'InsertEnter', 'CmdlineEnter' },
}

-- Load with file pattern
return {
  'user/lua-syntax',
  event = 'BufReadPre *.lua',
}

-- Load very lazily (after startup)
return {
  'user/plugin',
  event = 'VeryLazy',
}
```

## Command Trigger

Load a plugin when a user command is invoked.

### Syntax

```lua
return {
  'plugin/name',
  cmd = 'CommandName',
}
```

### Examples

```lua
-- Single command
return {
  'nvim-tree/nvim-tree.lua',
  cmd = { 'NvimTreeToggle', 'NvimTreeFocus' },
  opts = {},
}

-- Multiple commands
return {
  'user/plugin',
  cmd = { 'Cmd1', 'Cmd2', 'Cmd3' },
}
```

### How It Works

1. parcel.nvim creates a temporary stub command
2. When the user runs the command, the stub loads the plugin
3. The stub deletes itself and runs the actual command

## Keymap Trigger

Load a plugin when a key is pressed.

### Syntax

```lua
return {
  'plugin/name',
  keys = 'keyseq',
}
```

Or with options:

```lua
return {
  'plugin/name',
  keys = {
    { 'keyseq', function() ... end, mode = 'n', desc = 'Description' },
  },
}
```

### Examples

```lua
-- Simple key sequence
return {
  'folke/flash.nvim',
  keys = 's',
}

-- With function
return {
  'folke/flash.nvim',
  keys = {
    { 's', function() require('flash').jump() end, mode = { 'n', 'x', 'o' }, desc = 'Flash' },
    { 'S', function() require('flash').treesitter() end, mode = { 'n', 'x', 'o' }, desc = 'Flash Treesitter' },
  },
}

-- With command
return {
  'user/plugin',
  keys = { '<leader>p', '<cmd>PluginCmd<cr>', mode = 'n', desc = 'Run Plugin' },
}
```

### How It Works

1. parcel.nvim creates a temporary keymap
2. When the key is pressed, the plugin loads
3. The keymap deletes itself and re-feeds the keystrokes

## Filetype Trigger

Load a plugin when a file type is detected.

### Syntax

```lua
return {
  'plugin/name',
  ft = 'filetype',
}
```

### Examples

```lua
-- Single filetype
return {
  'rust-lang/rust.vim',
  ft = 'rust',
}

-- Multiple filetypes
return {
  'user/plugin',
  ft = { 'lua', 'vim', 'python' },
}
```

### Critical: Event Re-triggering

When using filetype triggers, parcel.nvim automatically re-triggers buffer events to ensure LSP/Treesitter attaches:

```lua
-- After loading, parcel.nvim does:
vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr })
vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr })
vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
```

This ensures that newly loaded plugins analyze the current buffer.

## Comparison

| Trigger  | Best For             | Overhead |
| -------- | -------------------- | -------- |
| Event    | General features     | Very low |
| Command  | CLI tools            | Very low |
| Keymap   | User-facing features | Low      |
| Filetype | Language tools       | Low      |

## Best Practices

### 1. Choose the Right Trigger

- **UI plugins** → Command or keymap trigger
- **Language servers** → Filetype trigger
- **General plugins** → Event trigger
- **Colorscheme** → No trigger (load eagerly)

### 2. Use Priority for Ordering

```lua
-- Load colorschemes early
return {
  'folke/tokyonight.nvim',
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}
```

### 3. Group Dependencies

Make sure dependencies are loaded before their parent:

```lua
return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
}
```

## Performance

parcel.nvim's lazy loading is optimized:

- **No package.loaders interception** - Unlike lazy.nvim, parcel doesn't intercept require()
- **Self-destructing triggers** - Autocmds delete themselves after first trigger
- **O(V + E) dependency resolution** - Efficient topological sorting

## Next Steps

- [Commands](commands.md) - CLI reference
- [Troubleshooting](troubleshooting.md) - Common issues
