---@module 'leanpack.commands'
local state = require("leanpack.state")

-- Lazy-loaded core modules
local hooks_mod = nil
local loader_mod = nil
local log_mod = nil

local function get_hooks()
    if not hooks_mod then hooks_mod = require("leanpack.hooks") end
    return hooks_mod
end

local function get_loader()
    if not loader_mod then loader_mod = require("leanpack.loader") end
    return loader_mod
end

local function get_log()
    if not log_mod then log_mod = require("leanpack.log") end
    return log_mod
end

local M = {}

---Validate command prefix
---@param prefix string
---@return boolean
local function validate_prefix(prefix)
  if prefix == "" then
    return true
  end
  -- Command must start with uppercase letter, can contain letters and digits
  return prefix:match("^[A-Z][A-Za-z0-9]*$") ~= nil
end

---Create a user command
---@param name string
---@param fn function
---@param opts table
---@return boolean
local function create_command(name, fn, opts)
  local ok, err = pcall(vim.api.nvim_create_user_command, name, fn, opts)
  if not ok then
    vim.notify(("Failed to create command %s: %s"):format(name, tostring(err)), vim.log.levels.ERROR)
    return false
  end
  return true
end

---Filter completion items by prefix
---@param list string[]
---@param prefix string
---@return string[]
local function filter_completions(list, prefix)
  if prefix == "" then
    return list
  end
  local lower_prefix = prefix:lower()
  return vim.tbl_filter(function(name)
    return name:lower():find(lower_prefix, 1, true) == 1
  end, list)
end

---Get plugin by name or notify error
---@param plugin_name string
---@return table?
local function get_plugin_or_notify(plugin_name)
  local ok, result = pcall(vim.pack.get, { plugin_name })
  if not ok or not result or not result[1] then
    vim.notify(('Plugin "%s" not found'):format(plugin_name), vim.log.levels.ERROR)
    return nil
  end
  return result[1]
end

---Clean unused plugins
function M.clean_unused()
  local to_delete = {}
  local installed = vim.pack.get() or {}

  for _, pack in ipairs(installed) do
    local src = pack.spec.src
    -- Don't clean leanpack itself
    if not state.get_entry(src) and not src:find("leanpack") then
      table.insert(to_delete, pack.spec.name)
    end
  end

  if #to_delete == 0 then
    vim.notify("No unused plugins to clean", vim.log.levels.INFO)
    get_log().info("No unused plugins to clean")
    return
  end

  local msg = ("Deleting %d unused plugin(s)..."):format(#to_delete)
  vim.notify(msg, vim.log.levels.INFO)
  get_log().info(msg)
  vim.pack.del(to_delete)
  get_log().info(("Deleted %d unused plugin(s)"):format(#to_delete))
end

---Setup commands
---@param prefix string
function M.setup(prefix)
  if not validate_prefix(prefix) then
    vim.notify(
      ('Invalid cmd_prefix "%s": must be empty or start with uppercase letter and contain only letters/digits'):format(
        prefix
      ),
      vim.log.levels.ERROR
    )
    return
  end

  -- :Leanpack {subcommand} [args]
  local ok = create_command(prefix, function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]
    local plugin_name = args[2] or ""

    if not subcommand then
      -- Open UI when no subcommand provided
      require("leanpack.ui").open()
      return
    end

    if subcommand == "update" then
      if plugin_name == "" then
        get_log().info("Updating all plugins")
        vim.pack.update(nil, { force = true })
        vim.schedule(function()
          vim.cmd("redraw")
          vim.notify("All plugins updated successfully", vim.log.levels.INFO)
          get_log().info("All plugins updated successfully")
        end)
      else
        if not get_plugin_or_notify(plugin_name) then
          return
        end
        get_log().info(("Updating plugin: %s"):format(plugin_name))
        vim.pack.update({ plugin_name }, { force = true })
        vim.schedule(function()
          vim.cmd("redraw")
          vim.notify("Updated " .. plugin_name, vim.log.levels.INFO)
          get_log().info(("Plugin updated successfully: %s"):format(plugin_name))
        end)
      end
    elseif subcommand == "clean" then
      M.clean_unused()
    elseif subcommand == "build" then
      if plugin_name == "" then
        if not opts.bang then
          vim.notify(("Use :%s build! to run build hooks for all plugins"):format(prefix), vim.log.levels.WARN)
          return
        end
        get_hooks().run_all_builds()
        return
      end

      local pack = get_plugin_or_notify(plugin_name)
      if not pack then
        return
      end

      local entry = state.get_entry(pack.spec.src)
      local spec = entry and entry.merged_spec
      if not spec or not spec.build then
        vim.notify(('Plugin "%s" has no build hook'):format(plugin_name), vim.log.levels.WARN)
        return
      end

      local pack_spec = state.get_pack_spec(pack.spec.src)
      if pack_spec then
        get_loader().load_plugin(pack_spec, { bang = true })
      end
      get_hooks().execute_build(spec.build, entry.plugin)
      local msg = ("Running build hook for %s"):format(plugin_name)
      vim.notify(msg, vim.log.levels.INFO)
      get_log().info(msg)
    elseif subcommand == "load" then
      if plugin_name == "" then
        if not opts.bang then
          vim.notify(("Use :%s load! to load all unloaded plugins"):format(prefix), vim.log.levels.WARN)
          return
        end
        local unloaded = state.get_unloaded_names()
        if #unloaded == 0 then
          vim.notify("All plugins are already loaded", vim.log.levels.INFO)
          return
        end
        for _, pack_spec in ipairs(state.get_all_pack_specs()) do
          local entry = state.get_entry(pack_spec.src)
          if entry and entry.load_status ~= "loaded" then
            get_loader().load_plugin(pack_spec)
          end
        end
        vim.notify(("Loaded %d plugin(s)"):format(#unloaded), vim.log.levels.INFO)
        return
      end

      local pack = get_plugin_or_notify(plugin_name)
      if not pack then
        return
      end

      local entry = state.get_entry(pack.spec.src)
      if not entry then
        vim.notify(('Plugin "%s" not found in registry'):format(plugin_name), vim.log.levels.ERROR)
        return
      end

      if entry.load_status == "loaded" then
        vim.notify(('Plugin "%s" is already loaded'):format(plugin_name), vim.log.levels.INFO)
        return
      end

      local pack_spec = state.get_pack_spec(pack.spec.src)
      if pack_spec then
        get_loader().load_plugin(pack_spec)
      end
      local msg = ("Loaded %s"):format(plugin_name)
      vim.notify(msg, vim.log.levels.INFO)
      get_log().info(msg)
    elseif subcommand == "delete" then
      if plugin_name == "" then
        if not opts.bang then
          vim.notify(("Use :%s delete! to confirm deletion of all installed plugin(s)"):format(prefix), vim.log.levels.WARN)
          return
        end
        local names = {}
        for _, pack_spec in ipairs(state.get_all_pack_specs()) do
          table.insert(names, pack_spec.name)
        end
        table.insert(names, "leanpack.nvim")

        vim.notify(("Deleting all %d installed plugin(s)..."):format(#names), vim.log.levels.INFO)
        vim.pack.del(names, { force = true })
        state.reset()
        vim.notify(
          "All plugins deleted. This can result in errors in your current session. Restart Neovim to re-install them or remove them from your spec.",
          vim.log.levels.WARN
        )
        return
      end

      local pack = get_plugin_or_notify(plugin_name)
      if not pack then
        return
      end

      vim.pack.del({ plugin_name }, { force = true })
      state.remove_plugin(plugin_name, pack.spec.src)
      local msg = ("%s deleted. This can result in errors in your current session. Restart Neovim to re-install it or remove it from your spec."):format(
          plugin_name
        )
      vim.notify(msg, vim.log.levels.WARN)
      get_log().warn(("Deleted plugin: %s"):format(plugin_name))
    elseif subcommand == "sync" then
      get_log().info("Syncing all plugins")
      vim.pack.update(nil, { force = true })
      M.clean_unused()
      vim.schedule(function()
        vim.cmd("redraw")
        vim.notify("Plugins synced successfully", vim.log.levels.INFO)
        get_log().info("Plugins synced successfully")
      end)
    elseif subcommand == "profile" then
      local profile = require("leanpack").get_profile_data()
      if next(profile) == nil or profile._total == 0 then
        vim.notify("No profiling data available. Enable profiling by passing `profiling = { enabled = true }` to leanpack.setup()", vim.log.levels.WARN)
        return
      end

      local lines = { "Leanpack.nvim Profile:" }
      local max_name = 0
      for name in pairs(profile) do
        if name ~= "_total" then
          max_name = math.max(max_name, #name)
        end
      end

      -- Sort by elapsed time descending
      local sorted = {}
      for name, elapsed in pairs(profile) do
        if name ~= "_total" then
          table.insert(sorted, { name = name, elapsed = elapsed })
        end
      end
      table.sort(sorted, function(a, b) return a.elapsed > b.elapsed end)

      for _, item in ipairs(sorted) do
        table.insert(lines, string.format("  %s: %6.2fms",
          item.name .. string.rep(" ", max_name - #item.name),
          item.elapsed
        ))
      end
      table.insert(lines, string.format("  %s: %6.2fms",
        "TOTAL" .. string.rep(" ", max_name - 5),
        profile._total
      ))

      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      vim.notify(("Unknown subcommand: %s"):format(subcommand), vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    bang = true,
    desc = "Leanpack plugin manager commands",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local parts = vim.split(cmd_line, "%s+", { trimempty = true })
      if #parts <= 2 then
        local subcommands = { "build", "clean", "delete", "load", "profile", "sync", "update" }
        return filter_completions(subcommands, arg_lead)
      elseif #parts == 3 then
        local subcommand = parts[2]
        if subcommand == "build" then
          return filter_completions(state.get_plugins_with_build(), arg_lead)
        elseif subcommand == "load" then
          local names = state.get_unloaded_names()
          table.sort(names, function(a, b)
            return a:lower() < b:lower()
          end)
          return filter_completions(names, arg_lead)
        elseif subcommand == "delete" or subcommand == "update" then
          return filter_completions(state.get_all_plugin_names(), arg_lead)
        end
      end
      return {}
    end,
  })

end

return M