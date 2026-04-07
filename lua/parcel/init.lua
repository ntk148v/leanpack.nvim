---@module 'parcel'
local state = require("parcel.state")
local spec_mod = require("parcel.spec")
local import_mod = require("parcel.import")
local deps_mod = require("parcel.deps")
local hooks = require("parcel.hooks")
local lazy_mod = require("parcel.lazy")
local loader = require("parcel.loader")
local commands = require("parcel.commands")
local lock = require("parcel.lock")
local checker = require("parcel.checker")
local git = require("parcel.git")

local M = {}

---@class parcel.ProcessContext
---@field vim_packs vim.pack.Spec[]
---@field srcs_with_init string[]
---@field startup_packs vim.pack.Spec[]
---@field lazy_packs vim.pack.Spec[]
---@field load boolean?
---@field confirm boolean?
---@field defaults parcel.Config.Defaults

---@return parcel.ProcessContext
local function create_context(opts)
  opts = opts or {}
  return {
    vim_packs = {},
    srcs_with_init = {},
    startup_packs = {},
    lazy_packs = {},
    load = opts.load,
    confirm = opts.confirm,
    defaults = opts.defaults or {},
  }
end

---Check Neovim version
---@return boolean
local function check_version()
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("parcel.nvim requires Neovim 0.12+", vim.log.levels.ERROR)
    return false
  end
  return true
end



---@class parcel.Config
---@field spec? parcel.Spec[] Plugin specifications
---@field cmd_prefix? string Command prefix, default "Parcel"
---@field defaults? parcel.Config.Defaults
---@field performance? parcel.Config.Performance

---@class parcel.Config.Defaults
---@field cond? boolean|(fun(plugin: parcel.Plugin):boolean) Global condition for all plugins
---@field confirm? boolean Ask for confirmation on install, default true

---@class parcel.Config.Performance
---@field vim_loader? boolean Enable vim.loader for faster startup, default true

local config = {
  cmd_prefix = "Parcel",
  defaults = { confirm = true },
  performance = { vim_loader = true },
  lockfile = {},
  checker = { enabled = false, frequency = 3600, notify = true },
  git = {},
}

---Process all specs and register plugins
---@param ctx parcel.ProcessContext
local function process_all(ctx)
  -- Setup build tracking before vim.pack.add
  hooks.setup_build_tracking()

  -- Register all plugins with vim.pack
  vim.pack.add(ctx.vim_packs, {
    load = ctx.load,
    confirm = ctx.confirm,
  })

  -- Update plugin paths after vim.pack.add
  for _, pack_spec in ipairs(ctx.vim_packs) do
    local entry = state.get_entry(pack_spec.src)
    if entry then
      -- Get the plugin path from vim.pack
      local ok, plugin_path = pcall(vim.fn.stdpath, "data")
      if ok then
        plugin_path = plugin_path .. "/pack/vim-pack/opt/" .. pack_spec.name
        if vim.fn.isdirectory(plugin_path) == 1 then
          entry.plugin = entry.plugin or { spec = pack_spec, path = "" }
          entry.plugin.path = plugin_path
        end
      end
    end
  end

  -- Setup lazy build tracking after vim.pack.add
  hooks.setup_lazy_build_tracking()

  -- Process startup plugins
  loader.process_startup(ctx)

  -- Process lazy plugins
  lazy_mod.process_lazy(ctx)

  -- Run pending builds
  hooks.run_pending_builds(ctx)

  -- Clear startup group
  vim.api.nvim_clear_autocmds({ group = state.startup_group })
end

---Register a spec and its dependencies
---@param spec parcel.Spec
---@param ctx parcel.ProcessContext
---@param is_dependency? boolean
local function register_spec(spec, ctx, is_dependency)
  -- Normalize spec
  local normalized, src = spec_mod.normalize_spec(spec, { defaults = ctx.defaults })
  if not normalized then
    return
  end

  normalized._is_dependency = is_dependency or false

  -- Get or create registry entry
  local entry = state.get_entry(src)
  local is_new = not entry
  if is_new then
    entry = {
      specs = {},
      load_status = "pending",
    }
    state.set_entry(src, entry)
  end

  -- Add spec to entry (may have multiple specs for same plugin)
  table.insert(entry.specs, normalized)

  -- Track init hooks (only once per src)
  if normalized.init and is_new then
    table.insert(ctx.srcs_with_init, src)
  end

  -- Track build hooks
  if normalized.build then
    state.mark_plugin_with_build(normalized.name)
  end

  -- Resolve dependencies
  local is_lazy_parent = normalized.lazy == true or lazy_mod.is_lazy(normalized, nil, src)
  local dep_specs = deps_mod.resolve_dependencies(normalized, ctx)
  for _, dep_spec in ipairs(dep_specs) do
    if is_lazy_parent and dep_spec.lazy == nil then
      dep_spec.lazy = true
    end
    register_spec(dep_spec, ctx, true)
  end

  -- Create vim.pack.Spec (only once per src)
  if is_new then
    local pack_spec = spec_mod.to_pack_spec(normalized)
    state.register_pack_spec(pack_spec)
    table.insert(ctx.vim_packs, pack_spec)

    -- Mark as unloaded
    state.mark_unloaded(normalized.name)
  end
end

---Finalize specs after all are registered
local function finalize_specs()
  for src, entry in pairs(state.get_all_entries()) do
    -- Merge specs
    if #entry.specs > 1 then
      entry.merged_spec = spec_mod.merge_specs(entry.specs)
    else
      entry.merged_spec = entry.specs[1]
    end

    -- Create plugin object
    local pack_spec = state.get_pack_spec(src)
    if pack_spec then
      entry.plugin = {
        spec = pack_spec,
        path = "", -- Will be set after vim.pack.add
      }
    end
  end
end

---Categorize plugins into startup and lazy
---@param ctx parcel.ProcessContext
local function categorize_plugins(ctx)
  for _, pack_spec in ipairs(state.get_all_pack_specs()) do
    local entry = state.get_entry(pack_spec.src)
    if entry and entry.merged_spec then
      if lazy_mod.is_lazy(entry.merged_spec, entry.plugin, pack_spec.src) then
        table.insert(ctx.lazy_packs, pack_spec)
      else
        table.insert(ctx.startup_packs, pack_spec)
      end
    end
  end
end

---Setup parcel.nvim
---@param opts? parcel.Config
function M.setup(opts)
  if not check_version() then
    return
  end

  if state.is_configured() then
    vim.notify("parcel.setup() has already been called", vim.log.levels.WARN)
    return
  end
  state.mark_setup()

  opts = opts or {}

  -- Load lockfile
  lock.load()

  -- Apply config
  if opts.cmd_prefix ~= nil then
    config.cmd_prefix = opts.cmd_prefix
  end
  if opts.defaults ~= nil then
    config.defaults = vim.tbl_extend("force", config.defaults, opts.defaults)
  end
  if opts.performance ~= nil then
    config.performance = vim.tbl_extend("force", config.performance, opts.performance)
  end
  if opts.lockfile ~= nil then
    config.lockfile = vim.tbl_extend("force", config.lockfile, opts.lockfile)
  end
  if opts.checker ~= nil then
    config.checker = vim.tbl_extend("force", config.checker, opts.checker)
  end
  if opts.git ~= nil then
    config.git = vim.tbl_extend("force", config.git or {}, opts.git)
    git.setup(config.git)
  end

  -- Enable vim.loader for performance
  if config.performance.vim_loader then
    vim.loader.enable()
  end

  -- Create processing context
  local ctx = create_context({
    confirm = config.defaults.confirm,
    defaults = config.defaults,
  })

  -- Import specs
  local spec = opts.spec or (opts[1] and opts) or nil
  if spec then
    local specs = import_mod.process_import_result(spec, { import_order = 0, seen = {} })
    for _, s in ipairs(specs) do
      register_spec(s, ctx)
    end
  end

  -- Auto-import from lua/plugins/ if no spec provided
  if not spec then
    local specs = import_mod.import_specs("plugins", { import_order = 0, seen = {} })
    for _, s in ipairs(specs) do
      register_spec(s, ctx)
    end
  end

  -- Finalize specs
  finalize_specs()

  -- Categorize into startup and lazy
  categorize_plugins(ctx)

  -- Process all plugins
  process_all(ctx)



  -- Setup commands
  commands.setup(config.cmd_prefix)

  -- Start update checker if enabled
  if config.checker.enabled then
    checker.start(config.checker.frequency)
  end
end

return M