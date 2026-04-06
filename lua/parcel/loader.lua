---@module 'parcel.loader'
local state = require("parcel.state")
local hooks = require("parcel.hooks")
local spec_mod = require("parcel.spec")
local keymap = require("parcel.keymap")

local M = {}

---Load a plugin and its dependencies
---@param pack_spec vim.pack.Spec
---@param opts? { bang?: boolean }
function M.load_plugin(pack_spec, opts)
  opts = opts or {}
  local entry = state.get_entry(pack_spec.src)

  if not entry then
    vim.notify(("Plugin %s not found in registry"):format(pack_spec.src), vim.log.levels.ERROR)
    return
  end

  -- Already loaded
  if entry.load_status == "loaded" then
    return
  end

  -- Circular dependency detection
  if entry.load_status == "loading" then
    vim.notify(
      ("Circular dependency detected: %s is already being loaded"):format(pack_spec.src),
      vim.log.levels.ERROR
    )
    return
  end

  entry.load_status = "loading"

  -- Load dependencies first
  local deps = state.get_dependencies(pack_spec.src)
  if deps then
    for dep_src in pairs(deps) do
      local dep_entry = state.get_entry(dep_src)
      if dep_entry and dep_entry.load_status ~= "loaded" then
        local dep_pack_spec = state.get_pack_spec(dep_src)
        if dep_pack_spec then
          M.load_plugin(dep_pack_spec, opts)
        else
          vim.notify(
            ("Dependency %s not found for %s"):format(dep_src, pack_spec.src),
            vim.log.levels.WARN
          )
        end
      end
    end
  end

  -- Load the plugin
  local spec = entry.merged_spec
  local plugin = entry.plugin

  if not plugin then
    vim.notify(("Cannot load %s: plugin not registered"):format(pack_spec.src), vim.log.levels.ERROR)
    return
  end

  -- Run packadd
  vim.cmd.packadd({ pack_spec.name, bang = opts.bang })

  -- Ensure plugin is in runtimepath for module resolution
  -- This is needed because packadd might not immediately update package.searchers
  local plugin_path = vim.fn.stdpath("data") .. "/pack/vim-pack/opt/" .. pack_spec.name
  if vim.fn.isdirectory(plugin_path) == 1 then
    package.loaded[pack_spec.name] = nil -- Clear any cached loads
  end

  -- Run config hook
  if spec.config or spec.opts ~= nil then
    hooks.run_config(pack_spec.src)
  end

  -- Apply keymaps
  local keys = spec_mod.resolve_field(spec.keys, plugin)
  if keys then
    keymap.apply_keys(keys)
  end

  -- Mark as loaded
  entry.load_status = "loaded"
  state.mark_loaded(pack_spec.name)
end

---Process startup plugins
---@param ctx table Processing context
function M.process_startup(ctx)
  -- Sort by priority (higher priority first)
  local srcs_with_init = {}
  for _, src in ipairs(ctx.srcs_with_init or {}) do
    table.insert(srcs_with_init, src)
  end
  table.sort(srcs_with_init, function(a, b)
    local entry_a = state.get_entry(a)
    local entry_b = state.get_entry(b)
    local pa = (entry_a and entry_a.merged_spec and entry_a.merged_spec.priority) or 50
    local pb = (entry_b and entry_b.merged_spec and entry_b.merged_spec.priority) or 50
    return pa > pb
  end)

  -- Run init hooks first
  for _, src in ipairs(srcs_with_init) do
    hooks.run_init(src)
  end

  -- Topological sort for dependencies
  local sorted_packs, lazy_deps_map = require("parcel.deps").toposort_startup(ctx.startup_packs)

  -- Load plugins in order
  for _, pack_spec in ipairs(sorted_packs) do
    vim.cmd.packadd({ pack_spec.name, bang = not ctx.load })
  end

  -- Run config hooks and apply keymaps
  for _, pack_spec in ipairs(sorted_packs) do
    -- Load lazy dependencies first
    local lazy_deps = lazy_deps_map[pack_spec.src]
    if lazy_deps then
      for _, dep_src in ipairs(lazy_deps) do
        local dep_pack = state.get_pack_spec(dep_src)
        if dep_pack then
          M.load_plugin(dep_pack, { bang = not ctx.load })
        end
      end
    end

    local entry = state.get_entry(pack_spec.src)
    if entry and entry.merged_spec then
      local spec = entry.merged_spec
      if spec.config or spec.opts ~= nil then
        hooks.run_config(pack_spec.src)
      end

      local keys = spec_mod.resolve_field(spec.keys, entry.plugin)
      if keys then
        keymap.apply_keys(keys)
      end
    end

    entry.load_status = "loaded"
    state.mark_loaded(pack_spec.name)
  end
end

return M