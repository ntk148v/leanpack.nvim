---@module 'leanpack.lazy_trigger.module'
local state = require("leanpack.state")
local log = require("leanpack.log")

local M = {}

-- Original loaders saved before we insert ours
local original_loaders = {}

-- Fast lookup: module name -> src (built at setup time)
local module_to_src = {}

-- Track modules we're currently loading to avoid recursion
local loading_modules = {}

---Custom loader that loads the plugin before requiring the module
local function leanpack_module_loader(modname)
    if loading_modules[modname] then
        return nil -- Avoid infinite recursion
    end

    local src = module_to_src[modname]
    if not src then
        return nil
    end

    local entry = state.get_entry(src)
    -- Only load if still pending (status could have changed between lookup and here)
    if not entry or entry.load_status ~= "pending" then
        return nil
    end

    loading_modules[modname] = true

    log.info(("Module trigger: loading plugin %s for module %s"):format(src, modname))

    local pack_spec = state.get_pack_spec(src)
    if pack_spec then
        require("leanpack.loader").load_plugin(pack_spec, { bang = true })
    end

    loading_modules[modname] = false

    -- Now try to load the module through the original loaders
    for _, loader in ipairs(original_loaders) do
        local result = loader(modname)
        if result then
            return result
        end
    end

    return nil
end

---Setup module trigger
---@param lazy_packs vim.pack.Spec[] List of lazy plugin specs
function M.setup(lazy_packs)
    -- Build fast lookup table: exact module name -> src
    -- Only for plugins that have an explicit `main` field
    for _, pack_spec in ipairs(lazy_packs or {}) do
        local entry = state.get_entry(pack_spec.src)
        if entry and entry.merged_spec and entry.merged_spec.main then
            local main = entry.merged_spec.main
            -- Register the exact main module name
            module_to_src[main] = pack_spec.src
            -- Also register common variants (with/without init)
            module_to_src[main .. ".init"] = pack_spec.src
        end
    end

    -- Don't install loader if nothing to trigger
    if next(module_to_src) == nil then
        log.info("Module trigger: no plugins with 'main' field, skipping")
        return
    end

    -- Save original loaders
    for i, loader in ipairs(package.loaders or package.searchers) do
        original_loaders[i] = loader
    end

    -- Insert our loader at position 2 (after preload, before file system)
    local loaders = package.loaders or package.searchers
    table.insert(loaders, 2, leanpack_module_loader)

    log.info("Module trigger loader installed for " .. tostring(#module_to_src) .. " module(s)")
end

return M
