---@module 'parcel.state'
local M = {}

---@class parcel.State
---@field is_setup boolean Whether setup() has been called
---@field spec_registry table<string, parcel.RegistryEntry> Registry keyed by src
---@field dependency_graph table<string, table<string, boolean>> src -> {dep_src -> true}
---@field reverse_dependency_graph table<string, table<string, boolean>> dep_src -> {parent_src -> true}
---@field src_to_pack_spec table<string, vim.pack.Spec> src -> vim.pack.Spec mapping
---@field registered_plugins vim.pack.Spec[] List of all registered vim.pack specs
---@field registered_plugin_names string[] List of plugin names
---@field plugin_names_with_build string[] Plugins that have build hooks
---@field unloaded_plugin_names table<string, boolean> Plugins not yet loaded
---@field src_with_pending_build table<string, boolean> Plugins with pending build hooks

local state = {
  is_setup = false,
  spec_registry = {},
  dependency_graph = {},
  reverse_dependency_graph = {},
  src_to_pack_spec = {},
  registered_plugins = {},
  registered_plugin_names = {},
  plugin_names_with_build = {},
  unloaded_plugin_names = {},
  src_with_pending_build = {},
}

-- Autocmd groups
local augroup = vim.api.nvim_create_augroup

M.startup_group = augroup("parcel_startup", { clear = true })
M.lazy_group = augroup("parcel_lazy", { clear = true })
M.lazy_build_group = augroup("parcel_lazy_build", { clear = true })

---Reset state to initial values
function M.reset()
  state.is_setup = false
  state.spec_registry = {}
  state.dependency_graph = {}
  state.reverse_dependency_graph = {}
  state.src_to_pack_spec = {}
  state.registered_plugins = {}
  state.registered_plugin_names = {}
  state.plugin_names_with_build = {}
  state.unloaded_plugin_names = {}
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
---@return parcel.RegistryEntry?
function M.get_entry(src)
  return state.spec_registry[src]
end

---Set registry entry for a plugin
---@param src string
---@param entry parcel.RegistryEntry
function M.set_entry(src, entry)
  state.spec_registry[src] = entry
end

---Get all registry entries
---@return table<string, parcel.RegistryEntry>
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
  state.src_to_pack_spec[pack_spec.src] = pack_spec
  table.insert(state.registered_plugins, pack_spec)
  table.insert(state.registered_plugin_names, pack_spec.name)
end

---Get vim.pack spec by src
---@param src string
---@return vim.pack.Spec?
function M.get_pack_spec(src)
  return state.src_to_pack_spec[src]
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

---Mark plugin as unloaded
---@param name string
function M.mark_unloaded(name)
  state.unloaded_plugin_names[name] = true
end

---Mark plugin as loaded
---@param name string
function M.mark_loaded(name)
  state.unloaded_plugin_names[name] = nil
end

---Check if plugin is unloaded
---@param name string
---@return boolean
function M.is_unloaded(name)
  return state.unloaded_plugin_names[name] ~= nil
end

---Get all unloaded plugin names
---@return string[]
function M.get_unloaded_names()
  return vim.tbl_keys(state.unloaded_plugin_names)
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
  state.src_to_pack_spec[src] = nil
  state.src_with_pending_build[src] = nil

  state.registered_plugins = vim.tbl_filter(function(spec)
    return spec.name ~= name
  end, state.registered_plugins)

  state.registered_plugin_names = vim.tbl_filter(function(n)
    return n ~= name
  end, state.registered_plugin_names)

  state.plugin_names_with_build = vim.tbl_filter(function(n)
    return n ~= name
  end, state.plugin_names_with_build)

  state.unloaded_plugin_names[name] = nil
end

---Get all registered plugin names
---@return string[]
function M.get_all_plugin_names()
  return state.registered_plugin_names
end

return M