---@module 'leanpack.hooks'
local log = require("leanpack.log")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

-- Lazy require to avoid circular dependency
local loader = nil
local function get_loader()
    if not loader then
        loader = require("leanpack.loader")
    end
    return loader
end

local M = {}

---Execute a hook function safely
---@param hook_name string
---@param plugin leanpack.Plugin
---@param hook function
---@return boolean success
local function execute_hook(hook_name, plugin, hook)
    local ok, err = pcall(hook, plugin)
    if not ok then
        vim.notify(("%s hook failed for %s: %s"):format(hook_name, plugin.spec.name, err), vim.log.levels.ERROR)
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

    -- Run explicit config function
    if type(spec.config) == "function" then
        return execute_hook("config", plugin, function()
            spec.config(plugin, opts)
        end)
    end

    -- Auto-setup with opts: require(main) and call setup()
    if spec.config == true or spec.opts ~= nil then
        local main = spec.main

        -- Auto-detect main module if not explicitly provided
        if not main and plugin and plugin.path and plugin.path ~= "" then
            main = spec_mod.detect_main(spec.name, plugin.path)
        end

        if not main then
            vim.schedule(function()
                vim.notify(
                    ("No main module for %s. Set `main` field or use `config = function() ... end`"):format(src),
                    vim.log.levels.WARN
                )
            end)
            return false
        end

        local ok, mod = pcall(require, main)
        if not ok then
            -- Plugin might not be installed yet or module path is incorrect
            -- Log warning instead of erroring to allow graceful recovery
            vim.schedule(function()
                vim.notify(
                    ("Failed to require '%s' for %s: %s. Plugin may not be installed yet."):format(main, src, mod),
                    vim.log.levels.WARN
                )
            end)
            return false
        end

        if type(mod) ~= "table" or type(mod.setup) ~= "function" then
            vim.schedule(function()
                vim.notify(("Module '%s' has no setup() function"):format(main), vim.log.levels.WARN)
            end)
            return false
        end

        local setup_ok, err = pcall(mod.setup, opts)
        if not setup_ok then
            error(("setup() failed for %s: %s"):format(src, err))
        end
    end

    return true
end

---Execute build hook
---@param build string|fun(plugin: leanpack.Plugin)
---@param plugin leanpack.Plugin
function M.execute_build(build, plugin)
    if type(build) == "string" then
        log.info(("Executing build command for %s: %s"):format(plugin.spec.name, build))
        vim.cmd(build)
    elseif type(build) == "function" then
        log.info(("Executing build function for %s"):format(plugin.spec.name))
        build(plugin)
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
---@param opts? { lazy?: boolean }
function M.setup_build_tracking(opts)
    opts = opts or {}
    local group = opts.lazy and state.lazy_build_group or state.startup_group

    vim.api.nvim_create_autocmd("PackChanged", {
        group = group,
        callback = function(event)
            if event.data.kind == "install" or event.data.kind == "update" then
                local src = event.data.spec.src
                if opts.lazy then
                    local entry = state.get_entry(src)
                    if entry and entry.merged_spec and entry.merged_spec.build then
                        local pack_spec = state.get_pack_spec(src)
                        if pack_spec then
                            get_loader().load_plugin(pack_spec, { bang = true })
                        end
                        M.execute_build(entry.merged_spec.build, entry.plugin)
                    end
                else
                    state.mark_pending_build(src)
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

    vim.notify(("Ran build hooks for %d plugin(s)"):format(count), vim.log.levels.INFO)
end

return M
