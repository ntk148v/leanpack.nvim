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
---Returns sorted packs with lazy deps loaded inline during traversal
---@param packs vim.pack.Spec[]
---@return vim.pack.Spec[] sorted_packs
function M.toposort_startup(packs)
  local src_to_pack = {}
  for _, pack in ipairs(packs) do
    src_to_pack[pack.src] = pack
  end

  local in_progress = {}
  local done = {}
  local result = {}

  local function visit(pack)
    if done[pack.src] then
      return
    end
    if in_progress[pack.src] then
      vim.notify(("Circular dependency: %s"):format(pack.src), vim.log.levels.WARN)
      return
    end

    in_progress[pack.src] = true

    -- Process dependencies: startup deps get sorted, lazy deps loaded now
    local deps = state.get_dependencies(pack.src)
    if deps then
      for dep_src in pairs(deps) do
        local dep_pack = src_to_pack[dep_src]
        if dep_pack then
          visit(dep_pack) -- Topological sort for startup deps
        else
          -- Lazy/optional dependency: load immediately if available
          local dep_entry = state.get_entry(dep_src)
          if dep_entry then
            local loader = require("parcel.loader")
            local dep_spec = state.get_pack_spec(dep_src)
            if dep_spec then
              loader.load_plugin(dep_spec)
            end
          end
        end
      end
    end

    in_progress[pack.src] = nil
    done[pack.src] = true
    table.insert(result, pack)
  end

  -- Sort by priority first (higher priority first)
  table.sort(packs, function(a, b)
    return ((a.data and a.data.priority) or 50) > ((b.data and b.data.priority) or 50)
  end)

  for _, pack in ipairs(packs) do
    visit(pack)
  end

  return result
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



return M