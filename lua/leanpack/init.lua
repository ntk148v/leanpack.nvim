local deps_mod = require("leanpack.deps")
local fs = require("leanpack.fs")
local hooks = require("leanpack.hooks")
local import_mod = require("leanpack.import")
local lazy_mod = require("leanpack.lazy")
local loader = require("leanpack.loader")
local log = require("leanpack.log")
local module_trigger = require("leanpack.lazy_trigger.module")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

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

local M = {}

-- Guard: only register save autocmd once
local save_cache_autocmd_registered = false

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
    sync = false,
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

---Process all specs and register plugins
---@param ctx leanpack.ProcessContext
local function process_all(ctx)
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

    local opt_path = vim.fn.stdpath("data") .. "/site/pack/core/opt/"

    local installed_startup_packs = {}
    local missing_packs = {}

    for _, p in ipairs(startup_vim_packs) do
        if vim.uv.fs_stat(opt_path .. p.name) then
            table.insert(installed_startup_packs, p)
        else
            table.insert(missing_packs, p)
        end
    end

    local installed_lazy_packs = {}
    for _, p in ipairs(lazy_vim_packs) do
        if vim.uv.fs_stat(opt_path .. p.name) then
            table.insert(installed_lazy_packs, p)
        else
            table.insert(missing_packs, p)
        end
    end

    -- Register installed startup plugins synchronously
    if #installed_startup_packs > 0 then
        vim.pack.add(installed_startup_packs, {
            load = ctx.load,
            confirm = false,
        })
    end

    -- Register installed lazy plugins
    if #installed_lazy_packs > 0 then
        local old_rtp = vim.o.rtp
        local old_path = package.path

        vim.pack.add(installed_lazy_packs, { load = false, confirm = false })

        -- Restore RTP and package.path
        vim.o.rtp = old_rtp
        package.path = old_path

        -- Source ftdetect scripts
        for _, p in ipairs(installed_lazy_packs) do
            local ftdetect_dir = opt_path .. p.name .. "/ftdetect"
            if fs.is_dir(ftdetect_dir) then
                fs.source_ftdetect_dir(ftdetect_dir)
            end
        end

        module_trigger.setup(installed_lazy_packs)
    end

    -- Compute plugin paths manually before async callbacks may run.
    for _, entry in pairs(state.get_all_entries()) do
        if entry.plugin and entry.plugin.spec then
            entry.plugin.path = opt_path .. entry.plugin.spec.name
        end
    end

    -- Background install missing plugins
    if #missing_packs > 0 then
        vim.notify(("Installing %d missing plugin(s) in background..."):format(#missing_packs), vim.log.levels.INFO)
        require("leanpack.job").run("install", missing_packs, function(success)
            if success then
                local m_startup = {}
                local m_lazy = {}
                for _, p in ipairs(missing_packs) do
                    if startup_srcs[p.src] then
                        table.insert(m_startup, p)
                    else
                        table.insert(m_lazy, p)
                    end
                end

                if #m_startup > 0 then
                    vim.pack.add(m_startup, { load = ctx.load, confirm = false })
                    for _, p in ipairs(m_startup) do
                        local entry = state.get_entry(p.src)
                        if entry and entry.load_status ~= "loaded" then
                            require("leanpack.loader").load_plugin(p)
                        end
                    end
                end

                if #m_lazy > 0 then
                    local old_rtp = vim.o.rtp
                    local old_path = package.path
                    vim.pack.add(m_lazy, { load = false, confirm = false })
                    vim.o.rtp = old_rtp
                    package.path = old_path

                    for _, p in ipairs(m_lazy) do
                        local ftdetect_dir = opt_path .. p.name .. "/ftdetect"
                        if fs.is_dir(ftdetect_dir) then
                            fs.source_ftdetect_dir(ftdetect_dir)
                        end
                    end
                    module_trigger.setup(m_lazy)
                end

                hooks.run_builds_for_packs(missing_packs)

                local ui_ok, ui = pcall(require, "leanpack.ui")
                if ui_ok and ui.refresh then
                    ui.refresh()
                end
                vim.notify(("Successfully installed %d plugin(s)"):format(#missing_packs), vim.log.levels.INFO)
            end
        end)
    end

    -- Setup lazy build tracking after vim.pack.add
    hooks.setup_build_tracking({ lazy = true })

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
    if opts.sync ~= nil then
        config.sync = opts.sync
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

    -- Finalize specs
    finalize_specs()

    -- Categorize into startup and lazy
    categorize_plugins(ctx)

    -- Process all plugins
    process_all(ctx)

    -- Auto-clean orphaned plugins (installed but not in config)
    if config.sync then
        local opt_path = vim.fn.stdpath("data") .. "/site/pack/core/opt/"
        local scan = vim.uv.fs_scandir(opt_path)
        if scan then
            local registered_names = {}
            for _, pack_spec in ipairs(state.get_all_pack_specs()) do
                registered_names[pack_spec.name] = true
            end
            -- Always protect leanpack itself
            registered_names["leanpack.nvim"] = true

            local orphans = {}
            while true do
                local name, type = vim.uv.fs_scandir_next(scan)
                if not name then
                    break
                end
                if type == "directory" and not registered_names[name] then
                    table.insert(orphans, name)
                end
            end

            if #orphans > 0 then
                log.info(("Sync: removing %d orphaned plugin(s): %s"):format(#orphans, table.concat(orphans, ", ")))
                vim.pack.del(orphans)
                vim.notify(("Removed %d plugin(s) no longer in config"):format(#orphans), vim.log.levels.INFO)
            end
        end
    end

    -- Save main module cache on exit (only register once)
    if not save_cache_autocmd_registered then
        save_cache_autocmd_registered = true
        vim.api.nvim_create_autocmd("VimLeavePre", {
            desc = "leanpack save cache",
            callback = function()
                local ok_cache, cache = pcall(require, "leanpack.cache")
                if ok_cache and cache.save then
                    cache.save()
                end
                state.save_main_cache()
            end,
        })
    end

    log.info("leanpack.nvim setup completed")
end

return M
