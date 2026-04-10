---@module 'leanpack.lazy'
local state = require("leanpack.state")
local spec_mod = require("leanpack.spec")
local deps = require("leanpack.deps")

local M = {}

---Check if a plugin should be lazy loaded
---@param spec leanpack.Spec
---@param plugin leanpack.Plugin?
---@param src? string
---@return boolean
function M.is_lazy(spec, plugin, src)
  -- Explicit lazy flag
  if spec.lazy ~= nil then
    return spec.lazy
  end

  -- Has lazy triggers
  local event = spec_mod.resolve_field(spec.event, plugin)
  local cmd = spec_mod.resolve_field(spec.cmd, plugin)
  local ft = spec_mod.resolve_field(spec.ft, plugin)
  local keys = spec_mod.resolve_field(spec.keys, plugin)

  if event or cmd or ft or (keys and #keys > 0) then
    return true
  end

  -- Is dependency of lazy plugin
  if src and deps.is_dependency_only(src) and spec.lazy == true then
    return true
  end

  return false
end

---Process lazy plugins and setup triggers
---@param ctx table Processing context
function M.process_lazy(ctx)
  -- Don't process if there are pending builds
  if state.has_pending_builds() then
    return
  end

  local event_handler = require("leanpack.lazy_trigger.event")
  local cmd_handler = require("leanpack.lazy_trigger.cmd")
  local keys_handler = require("leanpack.lazy_trigger.keys")
  local ft_handler = require("leanpack.lazy_trigger.ft")

  for _, pack_spec in ipairs(ctx.lazy_packs) do
    local entry = state.get_entry(pack_spec.src)
    if not entry or not entry.merged_spec then
      goto continue
    end

    local spec = entry.merged_spec
    local plugin = entry.plugin

    -- Setup event triggers
    local event = spec_mod.resolve_field(spec.event, plugin)
    if event then
      event_handler.setup(pack_spec, spec, event)
    end

    -- Setup filetype triggers
    local ft = spec_mod.resolve_field(spec.ft, plugin)
    if ft then
      ft_handler.setup(pack_spec, ft)
    end

    ::continue::
  end

  -- Setup command triggers
  cmd_handler.setup(ctx.lazy_packs)

  -- Setup keymap triggers
  keys_handler.setup(ctx.lazy_packs)
end

return M