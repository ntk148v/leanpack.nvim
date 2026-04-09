# Troubleshooting

Common issues and their solutions when using parcel.nvim.

## General Issues

### "Module 'parcel' not found"

**Cause:** parcel.nvim not in runtime path.

**Solution:**

1. Check if parcel.nvim is installed:

   ```bash
   ls ~/.local/share/nvim/site/pack/parcel/opt/parcel.nvim
   ```

2. Add to runtime path in `init.lua`:

   ```lua
   vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/site/pack/parcel/opt/parcel.nvim")
   ```

3. Or re-run bootstrap snippet at top of `init.lua`

### "Plugin not installing"

**Cause:** vim.pack not installing plugins.

**Solution:**

1. Check git is available:

   ```lua
   print(vim.fn.executable("git"))  -- Should be 1
   ```

2. Check `:checkhealth parcel`

3. Manually trigger install:
   ```vim
   :Parcel update
   ```

### "Lazy loading not working"

**Cause:** Trigger not set up correctly.

**Solution:**

1. Check plugin spec has trigger:

   ```lua
   -- Should have event, cmd, keys, or ft
   return {
     'plugin/name',
     event = 'InsertEnter',
   }
   ```

2. Check autocmd was created:

   ```vim
   :au ParcelLazy
   ```

3. Try loading manually:
   ```vim
   :Parcel load plugin-name
   ```

## Dependency Issues

### "Dependency not found"

**Cause:** Plugin dependency not in spec.

**Solution:**

1. Add dependency explicitly:

   ```lua
   {
     'parent/plugin',
     dependencies = { 'dependency/plugin' },
   }
   ```

2. Check for optional dependencies:
   ```lua
   { 'dep', optional = true }  -- Won't error if missing
   ```

### "Circular dependency detected"

**Cause:** Plugin A depends on B, B depends on A.

**Solution:** Fix your dependency graph - remove circular reference.

### "Modules not available in config"

**Cause:** Dependencies not loaded before config runs.

**Solution:**

1. Ensure dependency is listed:

   ```lua
   {
     'parent',
     dependencies = { 'dep' },
     config = function()
       require('dep')  -- Now available
     end,
   }
   ```

2. Or use lazy loading trigger

## Build Issues

### "Build hook not running"

**Cause:** Build not triggered or failed.

**Solution:**

1. Check plugin has build field:

   ```lua
   return {
     'plugin',
     build = 'make',  -- or function
   }
   ```

2. Run build manually:

   ```vim
   :Parcel build plugin-name
   ```

3. Check logs:
   ```bash
   cat ~/.local/share/nvim/lazy/parcel.log
   ```

### "Build fails"

**Cause:** Build command error.

**Solution:**

1. Test build command manually:

   ```bash
   cd ~/.local/share/nvim/site/pack/nvim-pack/opt/plugin
   make
   ```

2. Use function for complex builds:
   ```lua
   build = function()
     vim.fn.system({ 'cmake', '-S', '.', '-B', 'build' })
   end
   ```

## UI Issues

### "UI not opening"

**Cause:** UI function error.

**Solution:**

1. Check for errors:

   ```vim
   :messages
   ```

2. Try opening manually:
   ```lua
   require('parcel.ui').open()
   ```

### "UI keymaps not working"

**Cause:** Keymap conflict or not set.

**Solution:**

1. Check UI is open
2. Try `<Esc>` to exit
3. Check for keymap conflicts

## Performance Issues

### "Slow startup"

**Solution:**

1. Enable vim.loader:

   ```lua
   require('parcel').setup({
     performance = { vim_loader = true },
   })
   ```

2. Profile startup:

   ```bash
   nvim --startuptime startuptime.log +quit
   ```

3. Use lazy loading for more plugins

4. Check `:Parcel` to see loaded plugins

### "High memory usage"

**Solution:**

1. Clean unused plugins:

   ```vim
   :Parcel clean
   ```

2. Check loaded plugins:
   ```vim
   :Parcel
   ```

## Logging

### Enable Debug Logging

1. Check log file location:

   ```lua
   print(vim.fn.stdpath("log") .. "/parcel.log")
   ```

2. View recent logs:

   ```bash
   tail -f ~/.local/share/nvim/lazy/parcel.log
   ```

3. Check for errors in logs

## Health Check

Always start troubleshooting with:

```vim
:checkhealth parcel
```

This checks:

- Neovim version (needs 0.12+)
- vim.pack availability
- Git availability
- Unloaded plugins
- Pending builds
- Lockfile status

## Common Error Messages

| Error                          | Solution                                 |
| ------------------------------ | ---------------------------------------- |
| "Plugin not found in registry" | Add plugin to spec, run `:Parcel update` |
| "Circular dependency detected" | Fix circular deps in dependency list     |
| "Build hook failed"            | Check build command, check logs          |
| "Config failed"                | Check plugin's setup function            |

## Getting Help

1. Check `:checkhealth parcel`
2. Check log file
3. Search GitHub issues
4. Create minimal reproduction

## Reset

To reset parcel.nvim completely:

```bash
# Remove all plugins
rm -rf ~/.local/share/nvim/site/pack/nvim-pack/

# Remove lockfile
rm ~/.local/share/nvim/nvim-pack-lock.json

# Restart Neovim
```

Then run `:Parcel update` to reinstall.
