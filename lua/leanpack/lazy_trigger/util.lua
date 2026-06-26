---@module 'leanpack.lazy_trigger.util'
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

-- Default events to retrigger when no spec is available (safety net)
local DEFAULT_EVENTS = { "BufReadPre", "BufReadPost", "FileType" }

---Load a plugin and re-trigger events
---@param pack_spec vim.pack.Spec
---@param bufnr? number
function M.load_and_retrigger(pack_spec, bufnr)
    local entry = state.get_entry(pack_spec.src)
    -- Skip loading if already loading or loaded (e.g., another event fired during packadd)
    if entry and entry.load_status ~= "pending" then
        M.retrigger_events(bufnr or vim.api.nvim_get_current_buf(), entry.merged_spec)
        return
    end

    require("leanpack.loader").load_plugin(pack_spec)
    local loaded_entry = state.get_entry(pack_spec.src)
    M.retrigger_events(bufnr or vim.api.nvim_get_current_buf(), loaded_entry and loaded_entry.merged_spec)
end

---Resolve the set of events a plugin actually listens for from its spec
---@param spec table
---@return string[]
local function resolve_plugin_events(spec)
    if not spec then
        return {}
    end
    local raw = spec_mod.resolve_field(spec.event, spec)
    if not raw then
        return {}
    end
    local events = spec_mod.normalize_list(raw) or {}
    -- Filter out VeryLazy (it's not a real event to re-fire)
    local result = {}
    for _, ev in ipairs(events) do
        if ev ~= "VeryLazy" then
            table.insert(result, ev)
        end
    end
    return result
end

---Re-trigger events for the current buffer to ensure plugins attach correctly.
---Only fires events that the specific plugin actually listens for, rather than
---re-firing all known buffer events for every loaded plugin.
---@param bufnr number The buffer handle
---@param spec? table The plugin's merged spec (used to narrow events)
function M.retrigger_events(bufnr, spec)
    local plugin_events = resolve_plugin_events(spec)
    -- Fallback to defaults if spec has no specific events
    local events_to_fire = #plugin_events > 0 and plugin_events or DEFAULT_EVENTS

    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            for _, event in ipairs(events_to_fire) do
                vim.api.nvim_exec_autocmds(event, { buffer = bufnr, modeline = false })
            end
        end
    end)
end

return M
