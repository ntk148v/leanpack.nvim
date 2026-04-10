---@module 'leanpack.lazy_trigger.event'
local state = require("leanpack.state")
local loader = require("leanpack.loader")
local spec_mod = require("leanpack.spec")

local M = {}

---Check if value is an EventSpec
---@param value any
---@return boolean
local function is_event_spec(value)
  return type(value) == "table" and value.event ~= nil
end

---Normalize event value and apply fallback pattern
---@param spec leanpack.Spec
---@param event leanpack.EventValue
---@return leanpack.NormalizedEvent[]
local function normalize_events(spec, event)
  local result = {}
  local fallback_pattern = spec.pattern or "*"

  -- Convert to array
  local event_list = (type(event) == "string" or is_event_spec(event)) and { event } or event

  for _, ev in ipairs(event_list) do
    if type(ev) == "string" then
      -- Parse "EventName pattern" format
      local event_name, pattern = ev:match("^(%w+)%s+(.*)$")
      if event_name then
        table.insert(result, {
          events = { event_name },
          pattern = pattern,
        })
      else
        table.insert(result, {
          events = { ev },
          pattern = fallback_pattern,
        })
      end
    elseif is_event_spec(ev) then
      table.insert(result, {
        events = spec_mod.normalize_list(ev.event) or {},
        pattern = ev.pattern or fallback_pattern,
      })
    end
  end

  return result
end

---Split VeryLazy from other events
---@param events string[]
---@return boolean has_very_lazy, string[] other_events
local function split_very_lazy(events)
  local has_very_lazy = false
  local other_events = {}

  for _, event in ipairs(events) do
    if event == "VeryLazy" then
      has_very_lazy = true
    else
      table.insert(other_events, event)
    end
  end

  return has_very_lazy, other_events
end

---Setup event-based lazy loading
---@param pack_spec vim.pack.Spec
---@param spec leanpack.Spec
---@param event leanpack.EventValue
function M.setup(pack_spec, spec, event)
  local normalized_events = normalize_events(spec, event)

  for _, normalized in ipairs(normalized_events) do
    local has_very_lazy, other_events = split_very_lazy(normalized.events)

    -- VeryLazy: load after UIEnter
    if has_very_lazy then
      vim.api.nvim_create_autocmd("UIEnter", {
        group = state.lazy_group,
        once = true,
        callback = function()
          vim.schedule(function()
            loader.load_plugin(pack_spec)
          end)
        end,
      })
    end

    -- Other events
    if #other_events > 0 then
      vim.api.nvim_create_autocmd(other_events, {
        group = state.lazy_group,
        once = true,
        pattern = normalized.pattern,
        callback = function(ev)
          loader.load_plugin(pack_spec)
          require("leanpack.lazy_trigger.util").retrigger_events(ev.buf)
        end,
      })
    end
  end
end

return M