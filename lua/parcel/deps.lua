---@module 'parcel.deps'
local state = require("parcel.state")
local spec_mod = require("parcel.spec")

local M = {}

---Resolve dependencies for a spec
---@param spec parcel.Spec
---@param ctx table Processing context
---@return parcel.Spec[] dep_specs List of dependency specs
function M.resolve_dependencies(spec, ctx)
  if not spec.dependencies then
    return {}
  end

  local deps = spec.dependencies
  if type(deps) == "string" then
    deps = { deps }
  end

  local dep_specs = {}
  for _, dep in ipairs(deps) do
    if type(dep) == "string" then
      -- Convert short name to spec
      local dep_spec = { dep }
      local normalized, src = spec_mod.normalize_spec(dep_spec, ctx.defaults)
      if normalized then
        normalized._is_dependency = true
        -- Preserve optional flag from parent if not set
        if spec.optional and normalized.optional == nil then
          normalized.optional = spec.optional
        end
        table.insert(dep_specs, normalized)
        -- Track dependency relationship
        state.add_dependency(spec.src, src)
      end
    elseif type(dep) == "table" then
      -- Already a spec
      local normalized, src = spec_mod.normalize_spec(dep, ctx.defaults)
      if normalized then
        normalized._is_dependency = true
        -- Preserve optional flag from parent if not set
        if spec.optional and normalized.optional == nil then
          normalized.optional = spec.optional
        end
        table.insert(dep_specs, normalized)
        state.add_dependency(spec.src, src)
      end
    end
  end

  return dep_specs
end

---Topological sort for startup plugins respecting dependencies
---@param packs vim.pack.Spec[]
---@return vim.pack.Spec[] sorted_packs, table<string, string[]> lazy_deps_map
function M.toposort_startup(packs)
  local src_to_pack = {}
  for _, pack in ipairs(packs) do
    src_to_pack[pack.src] = pack
  end

  local in_progress = {}
  local done = {}
  local result = {}
  local lazy_deps_map = {}

  local function visit(pack)
    if done[pack.src] then
      return
    end

    if in_progress[pack.src] then
      vim.notify(
        ("Circular dependency detected in startup plugins involving: %s"):format(pack.src),
        vim.log.levels.WARN
      )
      return
    end

    in_progress[pack.src] = true

    local deps = state.get_dependencies(pack.src)
    if deps then
      for dep_src in pairs(deps) do
        local dep_pack = src_to_pack[dep_src]
        if dep_pack then
          visit(dep_pack)
        elseif state.get_entry(dep_src) then
          -- Dependency is a lazy plugin
          lazy_deps_map[pack.src] = lazy_deps_map[pack.src] or {}
          table.insert(lazy_deps_map[pack.src], dep_src)
        end
      end
    end

    in_progress[pack.src] = nil
    done[pack.src] = true
    result[#result + 1] = pack
  end

  -- Sort by priority first
  table.sort(packs, function(a, b)
    local pa = (a.data and a.data.priority) or 50
    local pb = (b.data and b.data.priority) or 50
    return pa > pb
  end)

  for _, pack in ipairs(packs) do
    visit(pack)
  end

  return result, lazy_deps_map
end

---Check if a plugin is only defined as a dependency
---@param src string
---@return boolean
function M.is_dependency_only(src)
  local entry = state.get_entry(src)
  if not entry then
    return false
  end
  for _, spec in ipairs(entry.specs) do
    if not spec._is_dependency then
      return false
    end
  end
  return true
end

---Check if any parent of a dependency is lazy (cached)
---@param dep_src string
---@return boolean
function M.has_lazy_parent(dep_src)
  local cached = state.get_cached_lazy_parent(dep_src)
  if cached ~= nil then
    return cached
  end

  local parents = state.get_reverse_dependencies(dep_src)
  if not parents then
    state.cache_lazy_parent(dep_src, false)
    return false
  end

  for parent_src in pairs(parents) do
    local entry = state.get_entry(parent_src)
    if entry and entry.merged_spec then
      local parent_spec = entry.merged_spec
      if parent_spec.lazy == true then
        state.cache_lazy_parent(dep_src, true)
        return true
      end
      if parent_spec.lazy == nil then
        -- Check if parent has lazy triggers
        local event = spec_mod.resolve_field(parent_spec.event, entry.plugin)
        local cmd = spec_mod.resolve_field(parent_spec.cmd, entry.plugin)
        local ft = spec_mod.resolve_field(parent_spec.ft, entry.plugin)
        local keys = spec_mod.resolve_field(parent_spec.keys, entry.plugin)
        if event or cmd or ft or (keys and #keys > 0) then
          state.cache_lazy_parent(dep_src, true)
          return true
        end
      end
    end
  end

  state.cache_lazy_parent(dep_src, false)
  return false
end

return M