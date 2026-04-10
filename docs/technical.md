# Technical Architecture

This document provides in-depth technical details about leanpack.nvim's implementation.

## Overview

leanpack.nvim is a thin layer over Neovim's native `vim.pack` (Neovim 0.12+) that adds lazy-loading, dependency management, and a native UI while delegating all disk operations to the native API.

## Architecture Blueprint

leanpack.nvim follows a 6-phase architectural blueprint:

### Phase 0: Automated Bootstrapping

Bootstrap snippet automatically installs leanpack.nvim if not present:

```lua
local lazypath = vim.fn.stdpath("data") .. "/site/pack/leanpack/opt/leanpack.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', 'https://github.com/ntk148v/leanpack.nvim', lazypath })
end
vim.opt.rtp:prepend(lazypath)
```

### Phase 1: Data Structures and State Delegation

- Single flat state table mapping plugin identifiers to configuration objects
- All disk operations delegated to vim.pack
- Native nvim-pack-lock.json for state tracking (no custom lockfile)

### Phase 2: Lightweight Lazy-Load Traps

Implements four trigger types without package.loaders interception:

1. **Event triggers** - Uses `nvim_create_autocmd` with `once = true`
2. **Command triggers** - Creates hollow user commands
3. **Keymap triggers** - Uses `vim.keymap.set` with self-deletion
4. **Filetype triggers** - Re-triggers BufReadPre/Post/FileType after load

### Phase 3: Recursive Dependency Traversal

- Depth-First Search (DFS) topological sort
- O(V + E) time complexity
- Circular dependency detection

### Phase 4: Build Hooks

- Listens for `PackChanged` autocommand events
- Triggers on `kind=install` and `kind=update`

### Phase 5: Command Orchestration

- Unified `:Leanpack` command with subcommands
- Native floating UI with scratch buffer
- Logging to `stdpath("log")/leanpack.log`

### Phase 6: Post-Load Re-triggering

- Re-triggers buffer events after filetype lazy load
- Ensures LSP/Treesitter attach to active buffers

## Module Structure

```
lua/leanpack/
├── init.lua          -- Entry point, setup()
├── state.lua         -- Centralized state management
├── spec.lua          -- Spec parsing, normalization
├── import.lua        -- Import from lua/plugins/
├── loader.lua        -- Plugin loading with deps
├── lazy.lua          -- Lazy loading detection
├── deps.lua          -- Topological sort
├── hooks.lua         -- init/config/build hooks
├── keymap.lua        -- Keymap utilities
├── commands.lua      -- :Leanpack commands
├── health.lua        -- :checkhealth integration
├── log.lua           -- Logging infrastructure
├── ui.lua            -- Native floating UI
└── lazy_trigger/
    ├── event.lua
    ├── cmd.lua
    ├── keys.lua
    └── ft.lua
```

## Key Implementation Details

### Lazy Loading

leanpack.nvim uses lightweight traps instead of package.loaders:

- **No require() interception** - This is computationally expensive
- **Explicit dependencies** - Instead of magic module loading
- **Self-destructing autocmds** - `once = true` prevents perpetual polling

### Dependency Resolution

Uses DFS topological sort:

1. Build dependency graph
2. Sort topologically
3. Load in correct order
4. Detect and prevent circular deps

### State Management

Centralized in `state.lua`:

- `state.entries` - Plugin registry
- `state.loaded` - Loaded plugins set
- `state.dependencies` - Dependency graph

### Logging

All operations logged to `stdpath("log")/leanpack.log`:

- `log.info()` - General info
- `log.warn()` - Warnings
- `log.error()` - Errors
- `log.debug()` - Debug info

## Performance Characteristics

| Metric                | Value                           |
| --------------------- | ------------------------------- |
| Startup overhead      | Minimal (delegates to vim.pack) |
| Lazy load trigger     | Microsecond delay               |
| Dependency resolution | O(V + E)                        |
| Memory usage          | Single flat state table         |

## Comparison with lazy.nvim

| Feature         | leanpack.nvim | lazy.nvim  |
| --------------- | ------------- | ---------- |
| package.loaders | ❌            | ✅         |
| vim.pack-based  | ✅            | ❌         |
| Native lockfile | ✅            | Custom     |
| Code size       | ~2,680 LOC    | ~3,100 LOC |
| bytecode cache  | vim.loader    | Custom     |

## Testing

Run tests:

```bash
./scripts/test
```

Tests use `mini.test` framework with isolated test environment.

## Debugging

1. Check logs: `vim.fn.stdpath("log") .. "/leanpack.log"`
2. Health check: `:checkhealth leanpack`
3. Startup profiling: `nvim --startuptime startuptime.log`

## References

- [vim.pack documentation](https://neovim.io/doc/user/pack/)
- [A Guide to vim.pack](https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack)
- [Architectural Analysis](../leanpacknvim-analysis.md)
