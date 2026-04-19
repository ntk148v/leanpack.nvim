local state = require("leanpack.state")

-- Lazy-loaded core modules
local spec_mod = nil
local function get_spec_mod()
    if not spec_mod then spec_mod = require("leanpack.spec") end
    return spec_mod
end

local M = {}

---Resolve dependencies for a spec
---@param spec leanpack.Spec
---@param ctx table Processing context
---@return leanpack.Spec[] dep_specs List of dependency specs
function M.resolve_dependencies(spec, ctx)
  if not spec.dependencies then
    return {}
  end

  local deps = spec.dependencies
  if type(deps) == "string" then
    deps = { deps }
  end

  local dep_specs = {}

  ---Register a single dependency spec
  ---@param normalized leanpack.Spec
  ---@param src string
  local function add_dep(normalized, src)
    normalized._is_dependency = true
    -- Preserve optional flag from parent if not set
    if spec.optional and normalized.optional == nil then
      normalized.optional = spec.optional
    end
    table.insert(dep_specs, normalized)
    -- Track dependency relationship
    state.add_dependency(spec.src, src)
  end

  for _, dep in ipairs(deps) do
    if type(dep) == "string" then
      -- Convert short name to spec
      local normalized, src = get_spec_mod().normalize_spec({ dep }, ctx.defaults)
      if normalized then
        add_dep(normalized, src)
      end
    elseif type(dep) == "table" then
      -- Check if this is a multi-string list (lazy.nvim format):
      -- { "owner/plugin-a", "owner/plugin-b", "owner/plugin-c" }
      -- All numeric keys are strings → treat each as a separate dependency
      local is_multi_string = #dep > 1
      if is_multi_string then
        local all_strings = true
        for i = 1, #dep do
          if type(dep[i]) ~= "string" then
            all_strings = false
            break
          end
        end
        is_multi_string = all_strings
      end

      if is_multi_string then
        -- Each string is a separate dependency
        for _, name in ipairs(dep) do
          local normalized, src = get_spec_mod().normalize_spec({ name }, ctx.defaults)
          if normalized then
            add_dep(normalized, src)
          end
        end
      else
        -- Single spec table (e.g., { "owner/plugin", opts = {} })
        local normalized, src = get_spec_mod().normalize_spec(dep, ctx.defaults)
        if normalized then
          add_dep(normalized, src)
        end
      end
    end
  end

  return dep_specs
end

---Topological sort for startup plugins respecting dependencies
---Returns sorted packs (pure sort, no side effects)
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

    -- Visit dependencies first (only those in the startup set)
    local deps = state.get_dependencies(pack.src)
    if deps then
      for dep_src in pairs(deps) do
        local dep_pack = src_to_pack[dep_src]
        if dep_pack then
          visit(dep_pack)
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