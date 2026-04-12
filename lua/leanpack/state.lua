---@module 'leanpack.state'
local M = {}

---@class leanpack.State
---@field is_setup boolean Whether setup() has been called
---@field spec_registry table<string, leanpack.RegistryEntry> Registry keyed by src
---@field dependency_graph table<string, table<string, boolean>> src -> {dep_src -> true}
---@field reverse_dependency_graph table<string, table<string, boolean>> dep_src -> {parent_src -> true}
---@field registered_plugins vim.pack.Spec[] List of all registered vim.pack specs
---@field plugin_names_with_build string[] Plugins that have build hooks
---@field src_with_pending_build table<string, boolean> Plugins with pending build hooks

local state = {
    is_setup = false,
    spec_registry = {},
    name_to_src = {},
    dependency_graph = {},
    reverse_dependency_graph = {},
    registered_plugins = {},
    plugin_names_with_build = {},
    src_with_pending_build = {},
}

-- Autocmd groups
local augroup = vim.api.nvim_create_augroup

M.startup_group = augroup("leanpack_startup", { clear = true })
M.lazy_group = augroup("leanpack_lazy", { clear = true })
M.lazy_build_group = augroup("leanpack_lazy_build", { clear = true })

---Reset state to initial values
function M.reset()
    state.is_setup = false
    state.spec_registry = {}
    state.name_to_src = {}
    state.dependency_graph = {}
    state.reverse_dependency_graph = {}
    state.registered_plugins = {}
    state.plugin_names_with_build = {}
    state.src_with_pending_build = {}
end

---Check if setup has been called
---@return boolean
function M.is_configured()
    return state.is_setup
end

---Mark setup as complete
function M.mark_setup()
    state.is_setup = true
end

---Get registry entry for a plugin
---@param src string
---@return leanpack.RegistryEntry?
function M.get_entry(src)
    return state.spec_registry[src]
end

---Set registry entry for a plugin
---@param src string
---@param entry leanpack.RegistryEntry
function M.set_entry(src, entry)
    state.spec_registry[src] = entry
    if entry.merged_spec and entry.merged_spec.name then
        state.name_to_src[entry.merged_spec.name] = src
    elseif entry.specs and entry.specs[1] and entry.specs[1].name then
        state.name_to_src[entry.specs[1].name] = src
    end
end

---Get all registry entries
---@return table<string, leanpack.RegistryEntry>
function M.get_all_entries()
    return state.spec_registry
end

---Add dependency relationship
---@param parent_src string
---@param dep_src string
function M.add_dependency(parent_src, dep_src)
    state.dependency_graph[parent_src] = state.dependency_graph[parent_src] or {}
    state.dependency_graph[parent_src][dep_src] = true

    state.reverse_dependency_graph[dep_src] = state.reverse_dependency_graph[dep_src] or {}
    state.reverse_dependency_graph[dep_src][parent_src] = true
end

---Get dependencies for a plugin
---@param src string
---@return table<string, boolean>?
function M.get_dependencies(src)
    return state.dependency_graph[src]
end

---Get reverse dependencies (parents) for a plugin
---@param src string
---@return table<string, boolean>?
function M.get_reverse_dependencies(src)
    return state.reverse_dependency_graph[src]
end

---Register a vim.pack spec
---@param pack_spec vim.pack.Spec
function M.register_pack_spec(pack_spec)
    local entry = M.get_entry(pack_spec.src)
    if entry then
        entry.plugin = entry.plugin or { spec = pack_spec, path = "" }
        entry.plugin.spec = pack_spec
    end
    state.name_to_src[pack_spec.name] = pack_spec.src
    table.insert(state.registered_plugins, pack_spec)
end

---Get vim.pack spec by src
---@param src string
---@return vim.pack.Spec?
function M.get_pack_spec(src)
    local entry = M.get_entry(src)
    return entry and entry.plugin and entry.plugin.spec
end

---Get all registered vim.pack specs
---@return vim.pack.Spec[]
function M.get_all_pack_specs()
    return state.registered_plugins
end

---Mark plugin as having build hook
---@param name string
function M.mark_plugin_with_build(name)
    if not vim.tbl_contains(state.plugin_names_with_build, name) then
        table.insert(state.plugin_names_with_build, name)
    end
end

---Get plugins with build hooks
---@return string[]
function M.get_plugins_with_build()
    return state.plugin_names_with_build
end

---Mark plugin as loaded
---@param name string
function M.mark_loaded(name)
    local src = state.name_to_src[name]
    if src then
        local entry = state.spec_registry[src]
        if entry then
            entry.load_status = "loaded"
            return
        end
    end

    -- Fallback to search if name mapping missed
    for _, entry in pairs(state.spec_registry) do
        if entry.merged_spec and entry.merged_spec.name == name then
            entry.load_status = "loaded"
            state.name_to_src[name] = entry.merged_spec.src
            break
        end
    end
end

---Mark plugin as unloaded
---@param name string
function M.mark_unloaded(name)
    local src = state.name_to_src[name]
    if src then
        local entry = state.spec_registry[src]
        if entry then
            entry.load_status = "pending"
            return
        end
    end

    -- Fallback to search if name mapping missed
    for _, entry in pairs(state.spec_registry) do
        if entry.merged_spec and entry.merged_spec.name == name then
            entry.load_status = "pending"
            state.name_to_src[name] = entry.merged_spec.src
            return
        end
    end

    -- If plugin not in registry, create a minimal entry
    state.spec_registry[name] = {
        specs = {},
        load_status = "pending",
        merged_spec = { name = name, src = name },
    }
    state.name_to_src[name] = name
end

---Check if plugin is unloaded
---@param name string
---@return boolean
function M.is_unloaded(name)
    local src = state.name_to_src[name]
    if src then
        local entry = state.spec_registry[src]
        if entry then
            return entry.load_status ~= "loaded"
        end
    end

    for _, entry in pairs(state.spec_registry) do
        if entry.merged_spec and entry.merged_spec.name == name then
            state.name_to_src[name] = entry.merged_spec.src
            return entry.load_status ~= "loaded"
        end
    end
    return false
end

---Get all unloaded plugin names
---@return string[]
function M.get_unloaded_names()
    local names = {}
    for _, entry in pairs(state.spec_registry) do
        if entry.merged_spec and entry.load_status ~= "loaded" then
            table.insert(names, entry.merged_spec.name)
        end
    end
    return names
end

---Mark plugin for pending build
---@param src string
function M.mark_pending_build(src)
    state.src_with_pending_build[src] = true
end

---Clear pending build
---@param src string
function M.clear_pending_build(src)
    state.src_with_pending_build[src] = nil
end

---Get all pending builds
---@return table<string, boolean>
function M.get_pending_builds()
    return state.src_with_pending_build
end

---Check if has pending builds
---@return boolean
function M.has_pending_builds()
    return next(state.src_with_pending_build) ~= nil
end

---Clear all pending builds
function M.clear_all_pending_builds()
    state.src_with_pending_build = {}
end

---Remove plugin from all state
---@param name string
---@param src string
function M.remove_plugin(name, src)
    state.spec_registry[src] = nil
    state.src_with_pending_build[src] = nil

    state.registered_plugins = vim.tbl_filter(function(spec)
        return spec.name ~= name
    end, state.registered_plugins)

    state.plugin_names_with_build = vim.tbl_filter(function(n)
        return n ~= name
    end, state.plugin_names_with_build)
end

---Get all registered plugin names
---@return string[]
function M.get_all_plugin_names()
    return vim.tbl_map(function(spec)
        return spec.name
    end, state.registered_plugins)
end

return M
