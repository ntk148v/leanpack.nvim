---@module 'leanpack'
local commands = require("leanpack.commands")
local deps_mod = require("leanpack.deps")
local hooks = require("leanpack.hooks")
local import_mod = require("leanpack.import")
local lazy_mod = require("leanpack.lazy")
local loader = require("leanpack.loader")
local log = require("leanpack.log")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

---@class leanpack.ProcessContext
---@field vim_packs vim.pack.Spec[]
---@field srcs_with_init string[]
---@field startup_packs vim.pack.Spec[]
---@field lazy_packs vim.pack.Spec[]
---@field load boolean?
---@field confirm boolean?
---@field defaults leanpack.Config.Defaults

---@return leanpack.ProcessContext
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
        vim.notify("leanpack.nvim requires Neovim 0.12+", vim.log.levels.ERROR)
        return false
    end
    return true
end

local config = {
    cmd_prefix = "Leanpack",
    defaults = { confirm = true },
    performance = {
        vim_loader = true,
        rtp_prune = true,
    },
}

local default_prune_list = {
    "gzip",
    "matchit",
    "matchparen",
    "netrwPlugin",
    "tarPlugin",
    "tohtml",
    "tutor",
    "zipPlugin",
}

---Prune runtime path by disabling built-in plugins
---@param list boolean|string[]
local function prune_rtp(list)
    if list == false then
        return
    end
    local plugins = list == true and default_prune_list or list
    for _, plugin in ipairs(plugins) do
        vim.g["loaded_" .. plugin] = 1
    end
end

---Check if a plugin directory appears to be broken (empty or missing key files)
---@param path string Plugin directory path
---@return boolean
local function is_plugin_broken(path)
    if vim.fn.isdirectory(path) ~= 1 then
        return true
    end

    -- Check for common plugin structures (lua/, plugin/, autoload/, ftplugin/)
    local has_structure = vim.fn.isdirectory(path .. "/lua") == 1
        or vim.fn.isdirectory(path .. "/plugin") == 1
        or vim.fn.isdirectory(path .. "/autoload") == 1
        or vim.fn.isdirectory(path .. "/ftplugin") == 1
        or vim.fn.isdirectory(path .. "/after") == 1

    -- If no standard structure, check if there are any .lua files
    if not has_structure then
        local lua_files = vim.fn.glob(path .. "/**/*.lua", true, true)
        if #lua_files == 0 then
            -- Also check for .vim files
            local vim_files = vim.fn.glob(path .. "/**/*.vim", true, true)
            if #vim_files == 0 then
                return true
            end
        end
    end

    return false
end

---Reinstall broken plugins by deleting and re-adding them
local function fix_broken_plugins()
    local broken = {}
    local installed = vim.pack.get() or {}

    for _, p in ipairs(installed) do
        if p.path and is_plugin_broken(p.path) then
            table.insert(broken, p.spec.name)
            log.warn(("Detected broken plugin: %s"):format(p.spec.name))
        end
    end

    if #broken > 0 then
        vim.notify(
            ("Detected %d broken plugin(s), reinstalling..."):format(#broken),
            vim.log.levels.WARN
        )

        -- Collect specs for broken plugins
        local broken_specs = {}
        for _, name in ipairs(broken) do
            for _, p in ipairs(installed) do
                if p.spec.name == name then
                    table.insert(broken_specs, p.spec)
                    break
                end
            end
        end

        -- Delete broken plugins
        vim.pack.del(broken, { force = true })

        -- Re-add the broken plugins after a short delay
        vim.defer_fn(function()
            vim.pack.add(broken_specs, { confirm = true })
        end, 100)
    end
end

---Process all specs and register plugins
---@param ctx leanpack.ProcessContext
local function process_all(ctx)
    -- Setup build tracking before vim.pack.add
    hooks.setup_build_tracking()

    -- Register all plugins with vim.pack
    vim.pack.add(ctx.vim_packs, {
        load = ctx.load,
        confirm = ctx.confirm,
    })

    -- Fix any broken plugins that failed to install properly
    fix_broken_plugins()

    -- Update plugin paths from vim.pack.get() (actual installed paths)
    local installed = vim.pack.get() or {}
    for _, p in ipairs(installed) do
        local entry = state.get_entry(p.spec.src)
        if entry and entry.plugin then
            entry.plugin.path = p.path
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
---@param spec leanpack.Spec
---@param ctx leanpack.ProcessContext
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
---@param ctx leanpack.ProcessContext
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

---Setup leanpack.nvim
---@param opts? leanpack.Config
function M.setup(opts)
    if not check_version() then
        return
    end

    if state.is_configured() then
        vim.notify("leanpack.setup() has already been called", vim.log.levels.WARN)
        return
    end
    state.mark_setup()

    -- Initialize logging
    log.init()
    log.info("leanpack.nvim setup started")

    opts = opts or {}

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

    -- Enable vim.loader for performance
    if config.performance.vim_loader then
        vim.loader.enable()
    end

    -- Prune RTP
    prune_rtp(config.performance.rtp_prune)

    -- Setup commands
    commands.setup(config.cmd_prefix)

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

    log.info("leanpack.nvim setup completed")
end

return M
