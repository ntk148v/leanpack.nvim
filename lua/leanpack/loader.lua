local hooks = require("leanpack.hooks")
local keymap = require("leanpack.keymap")
local log = require("leanpack.log")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

-- Cache of RTP entries to avoid repeated searches
local rtp_set = nil
local function get_rtp_set()
    if not rtp_set then
        rtp_set = {}
        for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
            rtp_set[path] = true
        end
    end
    return rtp_set
end

---Check whether a plugin or a dependency waits for the background install
---@param src string
---@param seen table<string, boolean>
---@return boolean
local function waits_for_install(src, seen)
    if seen[src] then
        return false
    end
    seen[src] = true
    local entry = state.get_entry(src)
    if entry and entry.installing then
        return true
    end
    for dep_src in pairs(state.get_dependencies(src) or {}) do
        if waits_for_install(dep_src, seen) then
            return true
        end
    end
    return false
end

-- Explicit cycle guard: prevents stack overflow if load_status transitions have bugs
local loading_set = {}

local function load_files_and_config(pack_spec, entry, opts)
    local src = pack_spec.src

    -- Add plugin to package.path immediately so dependencies can 'require' its modules
    local plugin_path = entry.plugin and entry.plugin.path
    if plugin_path and plugin_path ~= "" then
        local plugin_lua = plugin_path .. "/lua"
        if vim.fn.isdirectory(plugin_lua) == 1 then
            local p = plugin_lua .. "/?.lua;" .. plugin_lua .. "/?/init.lua"
            if not package.path:find(p, 1, true) then
                package.path = package.path .. ";" .. p
            end
        end
    end

    -- Load dependencies first
    local deps = state.get_dependencies(src)
    if deps then
        for dep_src in pairs(deps) do
            local dep_entry = state.get_entry(dep_src)
            if dep_entry and dep_entry.load_status ~= "loaded" and dep_entry.load_status ~= "failed" then
                local dep_pack_spec = state.get_pack_spec(dep_src)
                if dep_pack_spec then
                    -- Always source plugin files for dependencies to ensure Lua modules are available
                    M.load_plugin(dep_pack_spec, { bang = true })
                else
                    local is_optional = dep_entry.merged_spec and dep_entry.merged_spec.optional
                    if is_optional then
                        vim.notify(
                            ("Optional dependency %s not found for %s"):format(dep_src, src),
                            vim.log.levels.WARN
                        )
                    else
                        vim.notify(("Dependency %s not found for %s"):format(dep_src, src), vim.log.levels.ERROR)
                    end
                end
            end
        end
    end

    -- Load the plugin
    local spec = entry.merged_spec
    local plugin = entry.plugin

    if not plugin then
        vim.notify(("Cannot load %s: plugin not registered"):format(src), vim.log.levels.ERROR)
        entry.load_status = "failed"
        return
    end

    -- Run packadd if not already loaded bit vim.pack.add
    -- If ctx.load was true in setup, vim.pack.add already added it to RTP
    if opts.bang ~= false then
        if plugin_path and plugin_path ~= "" then
            -- Skip packadd if already on RTP to avoid redundant sourcing
            if not get_rtp_set()[plugin_path] then
                vim.cmd.packadd(pack_spec.name)
                -- Update cache since we just added it
                get_rtp_set()[plugin_path] = true
            end
        else
            -- If path not known, fall back to default packadd
            vim.cmd.packadd(pack_spec.name)
        end
    end

    -- Defer config hook for non-critical startup plugins to speed up first screen
    if spec.config or spec.opts ~= nil then
        if opts.force_defer then
            vim.schedule(function()
                hooks.run_config(src)
            end)
        else
            hooks.run_config(src)
        end
    end

    -- Apply keymaps
    local keys = spec_mod.resolve_field(spec.keys, plugin)
    if keys then
        keymap.apply_keys(keys)
    end

    -- Mark as loaded
    entry.load_status = "loaded"
    state.mark_loaded(pack_spec.name)
    log.info(("Successfully loaded plugin: %s"):format(pack_spec.name))
end

---Load a plugin and its dependencies
---@param pack_spec vim.pack.Spec
---@param opts? { bang?: boolean }
function M.load_plugin(pack_spec, opts)
    if not pack_spec or not pack_spec.src then
        return false
    end

    opts = opts or {}
    local src = pack_spec.src

    -- Explicit cycle guard (belt-and-suspenders with load_status check)
    if loading_set[src] then
        log.warn(("Circular load detected for: %s"):format(src))
        return
    end

    local entry = state.get_entry(src)

    if not entry then
        local msg = ("Plugin %s not found in registry"):format(src)
        vim.notify(msg, vim.log.levels.ERROR)
        log.error(msg)
        return
    end

    -- Already loaded or skipped
    if entry.load_status == "loaded" or entry.load_status == "skipped" then
        return
    end

    if entry.load_status == "loading" then
        local msg = ("Circular dependency detected involving plugin: %s"):format(src)
        vim.notify(msg, vim.log.levels.ERROR)
        log.error(msg)
        return
    end

    -- Check cond
    if entry.merged_spec and entry.merged_spec.cond ~= nil then
        local cond = entry.merged_spec.cond
        if type(cond) == "function" then
            local ok, result = pcall(cond, entry.plugin)
            if not ok then
                vim.notify(("cond failed for %s: %s"):format(pack_spec.name, result), vim.log.levels.ERROR)
            end
            cond = ok and result
        end
        if not cond then
            log.info(("Skipped loading plugin due to cond=false: %s"):format(pack_spec.name))
            entry.load_status = "skipped" -- Mark as skipped so dependents don't get stuck
            return
        end
    end

    if waits_for_install(src, {}) then
        -- The background install loads it when it finishes; status stays pending
        entry.load_after_install = true
        log.info(("Waiting for install before loading: %s"):format(pack_spec.name))
        return
    end

    loading_set[src] = true
    entry.load_status = "loading"
    log.info(("Loading plugin: %s"):format(pack_spec.name))

    local ok, err = pcall(load_files_and_config, pack_spec, entry, opts)
    loading_set[src] = nil
    if not ok then
        -- One bad plugin must not stop startup or stay stuck in "loading"
        entry.load_status = "failed"
        local msg = ("Failed to load %s: %s"):format(pack_spec.name, err)
        vim.notify(msg, vim.log.levels.ERROR)
        log.error(msg)
    end
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
    local sorted_packs = require("leanpack.deps").toposort_startup(ctx.startup_packs)

    -- A dependency's config must run before its dependent's config, so it cannot be deferred
    local is_dependency = {}
    for _, pack_spec in ipairs(sorted_packs) do
        for dep_src in pairs(state.get_dependencies(pack_spec.src) or {}) do
            is_dependency[dep_src] = true
        end
    end

    -- Load plugins and their configs in dependency order
    -- This ensures dependencies are loaded before dependents' configs run
    for _, pack_spec in ipairs(sorted_packs) do
        local entry = state.get_entry(pack_spec.src)
        local priority = (entry and entry.merged_spec and entry.merged_spec.priority) or 50
        -- Defer config for lower-priority startup plugins (strictly less than 50)
        -- This ensures that colorschemes and other core plugins set to default priority 50
        -- still load synchronously to avoid race conditions with init.lua overrides.
        local force_defer = priority < 50 and not is_dependency[pack_spec.src]
        -- Use load_plugin which handles dependency loading recursively
        M.load_plugin(pack_spec, { bang = not ctx.load, force_defer = force_defer })
    end
end

return M
