---@module 'parcel.commands'
local state = require("parcel.state")
local hooks = require("parcel.hooks")
local loader = require("parcel.loader")
local lock = require("parcel.lock")

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
    -- Don't clean parcel itself
    if not state.get_entry(src) and not src:find("parcel") then
      table.insert(to_delete, pack.spec.name)
    end
  end

  if #to_delete == 0 then
    vim.notify("No unused plugins to clean", vim.log.levels.INFO)
    return
  end

  vim.notify(("Deleting %d unused plugin(s)..."):format(#to_delete), vim.log.levels.INFO)
  vim.pack.del(to_delete)
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

  -- :Parcel {subcommand} [args]
  local ok = create_command(prefix, function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]
    local plugin_name = args[2] or ""

    if not subcommand then
      -- Open UI when no subcommand provided
      require("parcel.ui").open()
      return
    end

    if subcommand == "update" then
      if plugin_name == "" then
        vim.pack.update()
      else
        if not get_plugin_or_notify(plugin_name) then
          return
        end
        vim.pack.update({ plugin_name })
      end
      lock.save()
    elseif subcommand == "clean" then
      M.clean_unused()
    elseif subcommand == "build" then
      if plugin_name == "" then
        if not opts.bang then
          vim.notify(("Use :%s build! to run build hooks for all plugins"):format(prefix), vim.log.levels.WARN)
          return
        end
        hooks.run_all_builds()
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
        loader.load_plugin(pack_spec, { bang = true })
      end
      hooks.execute_build(spec.build, entry.plugin)
      vim.notify(("Running build hook for %s"):format(plugin_name), vim.log.levels.INFO)
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
            loader.load_plugin(pack_spec)
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

      loader.load_plugin(pack.spec)
      vim.notify(("Loaded %s"):format(plugin_name), vim.log.levels.INFO)
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
        table.insert(names, "parcel.nvim")

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
      vim.notify(
        ("%s deleted. This can result in errors in your current session. Restart Neovim to re-install it or remove it from your spec."):format(
          plugin_name
        ),
        vim.log.levels.WARN
      )
    else
      vim.notify(("Unknown subcommand: %s"):format(subcommand), vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
    bang = true,
    desc = "Parcel plugin manager commands",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local parts = vim.split(cmd_line, "%s+", { trimempty = true })
      if #parts <= 2 then
        local subcommands = { "build", "clean", "delete", "load", "update" }
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