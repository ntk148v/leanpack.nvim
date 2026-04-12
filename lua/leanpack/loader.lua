---@module 'leanpack.loader'
local hooks = require("leanpack.hooks")
local keymap = require("leanpack.keymap")
local log = require("leanpack.log")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

---Load a plugin and its dependencies
---@param pack_spec vim.pack.Spec
---@param opts? { bang?: boolean }
function M.load_plugin(pack_spec, opts)
    opts = opts or {}
    local entry = state.get_entry(pack_spec.src)

    if not entry then
        local msg = ("Plugin %s not found in registry"):format(pack_spec.src)
        vim.notify(msg, vim.log.levels.ERROR)
        log.error(msg)
        return
    end

    -- Already loaded
    if entry.load_status == "loaded" then
        return
    end

    -- Circular dependency detection
    if entry.load_status == "loading" then
        local msg = ("Circular dependency detected: %s is already being loaded"):format(pack_spec.src)
        vim.notify(msg, vim.log.levels.ERROR)
        log.error(msg)
        return
    end

    entry.load_status = "loading"
    log.info(("Loading plugin: %s"):format(pack_spec.name))

    -- Load dependencies first
    local deps = state.get_dependencies(pack_spec.src)
    if deps then
        for dep_src in pairs(deps) do
            local dep_entry = state.get_entry(dep_src)
            if dep_entry and dep_entry.load_status ~= "loaded" then
                local dep_pack_spec = state.get_pack_spec(dep_src)
                if dep_pack_spec then
                    -- Always source plugin files for dependencies to ensure Lua modules are available
                    M.load_plugin(dep_pack_spec, { bang = true })
                else
                    local is_optional = dep_entry.merged_spec and dep_entry.merged_spec.optional
                    if is_optional then
                        vim.notify(
                            ("Optional dependency %s not found for %s"):format(dep_src, pack_spec.src),
                            vim.log.levels.WARN
                        )
                    else
                        vim.notify(
                            ("Dependency %s not found for %s"):format(dep_src, pack_spec.src),
                            vim.log.levels.ERROR
                        )
                    end
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

    -- Run packadd if not already loaded by vim.pack.add
    -- If ctx.load was true in setup, vim.pack.add already added it to RTP
    if opts.bang ~= false then
        vim.cmd.packadd(pack_spec.name)
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
    log.info(("Successfully loaded plugin: %s"):format(pack_spec.name))
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

    -- Load plugins and their configs in dependency order
    -- This ensures dependencies are loaded before dependents' configs run
    for _, pack_spec in ipairs(sorted_packs) do
        -- Use load_plugin which handles dependency loading recursively
        M.load_plugin(pack_spec, { bang = not ctx.load })
    end
end

return M
