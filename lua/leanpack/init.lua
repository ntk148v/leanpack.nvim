local state = require("leanpack.state")
local deps_mod = require("leanpack.deps")
local hooks = require("leanpack.hooks")
local import_mod = require("leanpack.import")
local lazy_mod = require("leanpack.lazy")
local loader = require("leanpack.loader")
local log = require("leanpack.log")
local spec_mod = require("leanpack.spec")
local module_trigger = require("leanpack.lazy_trigger.module")

-- Lazy-loaded modules (only required when actually used)
local commands = nil
local ui_mod = nil
local health_mod = nil

local function get_commands()
    if not commands then
        commands = require("leanpack.commands")
    end
    return commands
end

local function get_ui()
    if not ui_mod then
        ui_mod = require("leanpack.ui")
    end
    return ui_mod
end

local function get_health()
    if not health_mod then
        health_mod = require("leanpack.health")
    end
    return health_mod
end

-- Profiling data
local profile_data = {
    enabled = false,
    phases = {},
}

---Start timing a phase
---@param name string
local function profile_start(name)
    if profile_data.enabled then
        profile_data.phases[name] = { start = vim.uv.hrtime() }
    end
end

---End timing a phase
---@param name string
local function profile_end(name)
    if profile_data.enabled and profile_data.phases[name] then
        local elapsed = (vim.uv.hrtime() - profile_data.phases[name].start) / 1e6 -- ms
        profile_data.phases[name].elapsed = elapsed
    end
end

---Get profiling results
---@return table
local function get_profile_data()
    local result = {}
    local total = 0
    for name, data in pairs(profile_data.phases) do
        result[name] = data.elapsed or 0
        total = total + (data.elapsed or 0)
    end
    result._total = total
    return result
end

local M = {}

---Enable profiling
---@param enabled boolean
function M.set_profiling(enabled)
    profile_data.enabled = enabled
    if enabled then
        profile_data.phases = {}
    end
end

---Get profiling results
---@return table
function M.get_profile_data()
    return get_profile_data()
end

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
    checker = {
        enabled = false,
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
    local path_stat = vim.uv.fs_stat(path)
    if not path_stat or path_stat.type ~= "directory" then
        return true
    end

    -- Check for common plugin structures (lua/, plugin/, autoload/, ftplugin/)
    local has_structure = false
    for _, subdir in ipairs({ "lua", "plugin", "autoload", "ftplugin", "after" }) do
        local stat = vim.uv.fs_stat(path .. "/" .. subdir)
        if stat and stat.type == "directory" then
            has_structure = true
            break
        end
    end

    -- If no standard structure, check if there are any .lua files
    if not has_structure then
        local fd = vim.uv.fs_scandir(path)
        if not fd then
            return true
        end

        -- Check for files matching pattern recursively
        local function scan_for_files(dir, pattern)
            local dir_fd = vim.uv.fs_scandir(dir)
            if not dir_fd then
                return false
            end
            while true do
                local entry_name, type = vim.uv.fs_scandir_next(dir_fd)
                if not entry_name then
                    break
                end
                if type == "file" and entry_name:match(pattern) then
                    return true
                elseif type == "directory" then
                    if scan_for_files(dir .. "/" .. entry_name, pattern) then
                        return true
                    end
                end
            end
            return false
        end

        if not scan_for_files(path, "%.lua$") and not scan_for_files(path, "%.vim$") then
            return true
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
        vim.notify(("Detected %d broken plugin(s), reinstalling..."):format(#broken), vim.log.levels.WARN)

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
    profile_start("vim.pack.add")

    -- Setup build tracking before vim.pack.add
    hooks.setup_build_tracking()

    -- Only add startup plugins immediately (fast path)
    local startup_srcs = {}
    for _, p in ipairs(ctx.startup_packs) do
        startup_srcs[p.src] = true
    end
    local startup_vim_packs = {}
    local lazy_vim_packs = {}
    for _, p in ipairs(ctx.vim_packs) do
        if startup_srcs[p.src] then
            table.insert(startup_vim_packs, p)
        else
            table.insert(lazy_vim_packs, p)
        end
    end

    -- Register startup plugins with vim.pack
    vim.pack.add(startup_vim_packs, {
        load = ctx.load,
        confirm = ctx.confirm,
    })

    -- Register lazy plugins with vim.pack (without loading) to trigger background installation
    if #lazy_vim_packs > 0 then
        vim.pack.add(lazy_vim_packs, { load = false, confirm = false })
        -- Defer lazy plugin registration but set up module triggers synchronously
        -- so that early autocmds (like BufReadPre) can still intercept requires.
        module_trigger.setup(lazy_vim_packs)
    end

    profile_end("vim.pack.add")
    profile_start("fix_broken_plugins")

    -- Fix any broken plugins that failed to install properly
    if config.checker.enabled then
        fix_broken_plugins()
    end

    profile_end("fix_broken_plugins")
    -- Compute plugin paths manually instead of calling slow vim.pack.get()
    local data_path = vim.fn.stdpath("data")
    local opt_path = data_path .. "/site/pack/core/opt/"
    local start_path = data_path .. "/site/pack/core/start/"

    for _, entry in pairs(state.get_all_entries()) do
        if entry.plugin and entry.plugin.spec then
            local is_lazy = entry.merged_spec and entry.merged_spec.lazy
            local base = is_lazy and opt_path or start_path
            entry.plugin.path = base .. entry.plugin.spec.name
        end
    end

    profile_end("update_paths")

    -- Setup lazy build tracking after vim.pack.add
    hooks.setup_build_tracking({ lazy = true })

    profile_start("process_startup")

    -- Process startup plugins
    loader.process_startup(ctx)

    profile_end("process_startup")
    profile_start("process_lazy")

    -- Process lazy plugins
    lazy_mod.process_lazy(ctx)

    profile_end("process_lazy")
    profile_start("run_pending_builds")

    -- Run pending builds
    hooks.run_pending_builds(ctx)

    profile_end("run_pending_builds")

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

    -- Propagate defaults.lazy if not explicitly set
    if normalized.lazy == nil and ctx.defaults.lazy ~= nil then
        normalized.lazy = ctx.defaults.lazy
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
        vim.notify("leanpack.setup() has already been called - appending new plugins", vim.log.levels.INFO)
    else
        state.mark_setup()
    end

    -- Initialize logging
    log.init()
    log.info("leanpack.nvim setup started")

    opts = opts or {}

    -- Support enabling profiling via opts
    if opts.profiling ~= nil then
        local enable_profiling = false
        if type(opts.profiling) == "boolean" then
            enable_profiling = opts.profiling
        elseif type(opts.profiling) == "table" and opts.profiling.enabled ~= nil then
            enable_profiling = opts.profiling.enabled
        end
        M.set_profiling(enable_profiling)
    end

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
    if opts.checker ~= nil then
        config.checker = vim.tbl_extend("force", config.checker, opts.checker)
    end

    -- Store plugins for direct specification
    local direct_plugins = opts.plugins

    -- Enable vim.loader for performance
    if config.performance.vim_loader then
        vim.loader.enable()
    end

    -- Prune RTP
    prune_rtp(config.performance.rtp_prune)

    -- Setup commands
    get_commands().setup(config.cmd_prefix)

    -- Create processing context
    local ctx = create_context({
        confirm = config.defaults.confirm,
        defaults = config.defaults,
    })

    -- Import specs
    profile_start("import_specs")
    local spec = direct_plugins or opts.spec or (opts[1] and opts) or nil
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
    profile_end("import_specs")

    -- Finalize specs
    profile_start("finalize_specs")
    finalize_specs()
    profile_end("finalize_specs")

    -- Categorize into startup and lazy
    profile_start("categorize_plugins")
    categorize_plugins(ctx)
    profile_end("categorize_plugins")

    -- Process all plugins
    profile_start("process_all")
    process_all(ctx)
    profile_end("process_all")

    -- Save main module cache on exit
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            state.save_main_cache()
        end,
    })

    log.info("leanpack.nvim setup completed")
end

return M
