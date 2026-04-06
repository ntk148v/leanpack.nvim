---@module 'parcel.hooks'
local state = require("parcel.state")
local spec_mod = require("parcel.spec")

-- Lazy require to avoid circular dependency
local loader = nil
local function get_loader()
  if not loader then
    loader = require("parcel.loader")
  end
  return loader
end

local M = {}

---Execute a hook function safely
---@param hook_name string
---@param plugin parcel.Plugin
---@param hook function
---@return boolean success
local function execute_hook(hook_name, plugin, hook)
  local ok, err = pcall(hook, plugin)
  if not ok then
    vim.schedule(function()
      vim.notify(
        ("Failed to run %s hook for %s: %s"):format(hook_name, plugin.spec.name, err),
        vim.log.levels.ERROR
      )
    end)
    return false
  end
  return true
end

---Run init hook for a plugin
---@param src string
---@return boolean
function M.run_init(src)
  local entry = state.get_entry(src)
  if not entry or not entry.merged_spec then
    return false
  end

  local spec = entry.merged_spec
  local plugin = entry.plugin

  if spec.init then
    return execute_hook("init", plugin, spec.init)
  end

  return true
end

---Run config hook for a plugin
---@param src string
---@return boolean
function M.run_config(src)
  local entry = state.get_entry(src)
  if not entry or not entry.merged_spec then
    return false
  end

  local spec = entry.merged_spec
  local plugin = entry.plugin

  -- Resolve opts
  local opts = spec.opts
  if type(opts) == "function" then
    opts = opts(plugin, {}) or {}
  else
    opts = opts or {}
  end

  -- Run config function
  if type(spec.config) == "function" then
    return execute_hook("config", plugin, function()
      spec.config(plugin, opts)
    end)
  end

  -- Auto-setup with opts
  if spec.config == true or spec.opts ~= nil then
    local main = spec.main or spec_mod.detect_main(plugin)
    if not main then
      vim.schedule(function()
        vim.notify(
          ("Could not determine main module for %s. Set `main` explicitly or use `config = function() ... end`"):format(
            src
          ),
          vim.log.levels.WARN
        )
      end)
      return false
    end

    local ok, mod = pcall(require, main)
    if not ok then
      vim.schedule(function()
        vim.notify(
          ("Failed to require '%s' for %s: %s"):format(main, src, mod),
          vim.log.levels.ERROR
        )
      end)
      return false
    end

    if type(mod) ~= "table" or type(mod.setup) ~= "function" then
      vim.schedule(function()
        vim.notify(
          ("Module '%s' for %s has no setup() function"):format(main, src),
          vim.log.levels.WARN
        )
      end)
      return false
    end

    local setup_ok, err = pcall(mod.setup, opts)
    if not setup_ok then
      vim.schedule(function()
        vim.notify(
          ("Failed to run setup for %s: %s"):format(src, err),
          vim.log.levels.ERROR
        )
      end)
      return false
    end
  end

  return true
end

---Execute build hook
---@param build string|fun(plugin: parcel.Plugin)
---@param plugin parcel.Plugin
function M.execute_build(build, plugin)
  if type(build) == "string" then
    vim.schedule(function()
      vim.cmd(build)
    end)
  elseif type(build) == "function" then
    vim.schedule(function()
      build(plugin)
    end)
  end
end

---Run build hook for a plugin
---@param src string
---@return boolean
function M.run_build(src)
  local entry = state.get_entry(src)
  if not entry or not entry.merged_spec then
    return false
  end

  local spec = entry.merged_spec
  local plugin = entry.plugin

  if spec.build then
    M.execute_build(spec.build, plugin)
    return true
  end

  return false
end

---Setup build tracking for PackChanged events
function M.setup_build_tracking()
  vim.api.nvim_create_autocmd("PackChanged", {
    group = state.startup_group,
    callback = function(event)
      if event.data.kind == "install" or event.data.kind == "update" then
        state.mark_pending_build(event.data.spec.src)
      end
    end,
  })
end

---Setup lazy build tracking for PackChanged events
function M.setup_lazy_build_tracking()
  vim.api.nvim_create_autocmd("PackChanged", {
    group = state.lazy_build_group,
    callback = function(event)
      if event.data.kind == "install" or event.data.kind == "update" then
        local src = event.data.spec.src
        local entry = state.get_entry(src)
        if entry and entry.merged_spec and entry.merged_spec.build then
          local pack_spec = state.get_pack_spec(src)
          if pack_spec then
            get_loader().load_plugin(pack_spec, { bang = true })
          end
          M.execute_build(entry.merged_spec.build, entry.plugin)
        end
      end
    end,
  })
end

---Run all pending builds on startup
---@param ctx table Processing context
function M.run_pending_builds(ctx)
  if not state.has_pending_builds() then
    return
  end

  for src in pairs(state.get_pending_builds()) do
    local entry = state.get_entry(src)
    if entry and entry.merged_spec and entry.merged_spec.build then
      local pack_spec = state.get_pack_spec(src)
      if pack_spec then
        get_loader().load_plugin(pack_spec, { bang = not ctx.load })
      end
      M.execute_build(entry.merged_spec.build, entry.plugin)
    end
  end

  state.clear_all_pending_builds()
end

---Run build hooks for all plugins with build field
function M.run_all_builds()
  local count = 0

  for src, entry in pairs(state.get_all_entries()) do
    if entry.merged_spec and entry.merged_spec.build then
      local pack_spec = state.get_pack_spec(src)
      if pack_spec then
        get_loader().load_plugin(pack_spec, { bang = true })
      end
      M.execute_build(entry.merged_spec.build, entry.plugin)
      count = count + 1
    end
  end

  if count > 0 then
    vim.schedule(function()
      vim.notify(("Running build hooks for %d plugin(s)"):format(count), vim.log.levels.INFO)
    end)
  else
    vim.schedule(function()
      vim.notify("No plugins with build hooks found", vim.log.levels.INFO)
    end)
  end
end

return M