---@module 'parcel.lazy_trigger.module'
local state = require("parcel.state")
local loader = require("parcel.loader")
local spec_mod = require("parcel.spec")

local M = {}

---@type table<string, vim.pack.Spec>
local loaded_modules = {}

---Check if a module pattern matches a module name
---@param pattern string
---@param module_name string
---@return boolean
local function matches_pattern(pattern, module_name)
  -- Simple prefix/suffix matching
  if pattern:match("^%*") then
    local suffix = pattern:sub(2)
    return module_name:find(suffix, 1, true) ~= nil
  elseif pattern:match("%*$") then
    local prefix = pattern:sub(1, -2)
    return module_name:sub(1, #prefix) == prefix
  elseif pattern:match("^@") then
    -- lazy.nvim style: @ prefix means exact match or submodule
    local exact = pattern:sub(2)
    return module_name == exact or module_name:sub(1, #exact + 1) == exact .. "."
  else
    -- Exact match
    return module_name == pattern
  end
end

---Check if module name matches any pattern
---@param patterns string|string[]
---@param module_name string
---@return boolean
local function matches_any_pattern(patterns, module_name)
  local pattern_list = spec_mod.normalize_list(patterns) or {}
  for _, pattern in ipairs(pattern_list) do
    if matches_pattern(pattern, module_name) then
      return true
    end
  end
  return false
end

---Intercept require() to trigger lazy loading
---@param pack_spec vim.pack.Spec
---@param patterns string|string[]
local function setup_module_interceptor(pack_spec, patterns)
  local original_require = require
  local interceptor_installed = false

  -- Only install interceptor once per pattern set
  local pattern_key = vim.inspect(patterns)
  if loaded_modules[pattern_key] then
    return
  end
  loaded_modules[pattern_key] = pack_spec

  -- We use a metatable approach on package.loaded to intercept module loads
  -- This is more efficient than wrapping require itself
  local orig_loaders = package.loaders or package.loadlib

  -- Create a custom loader that checks our patterns
  local function parcel_module_loader(module_name)
    if matches_any_pattern(patterns, module_name) then
      -- Clear this loader so we don't call it again
      for i, loader_fn in ipairs(package.loaders or package.loadlib) do
        if loader_fn == parcel_module_loader then
          package.loaders[i] = function(mod)
            -- Just fall through to normal loading
            return original_require(mod)
          end
          break
        end
      end

      -- Trigger plugin load
      vim.schedule(function()
        loader.load_plugin(pack_spec)
      end)

      -- Return nil to let normal loaders handle the actual require
      return function(mod)
        return original_require(mod)
      end
    end
    return nil
  end

  -- Insert our loader at the front
  table.insert(package.loaders, 1, parcel_module_loader)
end

---Setup module-based lazy loading
---@param ctx table Processing context with lazy_packs
function M.setup(ctx)
  for _, pack_spec in ipairs(ctx.lazy_packs or {}) do
    local entry = state.get_entry(pack_spec.src)
    if not entry or not entry.merged_spec then
      goto continue
    end

    local spec = entry.merged_spec
    local plugin = entry.plugin

    -- Setup module triggers
    local module = spec_mod.resolve_field(spec.module, plugin)
    if module then
      setup_module_interceptor(pack_spec, module)
    end

    ::continue::
  end
end

---Cleanup function (for testing/reset)
function M.reset()
  loaded_modules = {}
end

return M
