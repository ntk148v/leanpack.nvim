---@module 'leanpack.lazy_trigger.util'
local M = {}

---Load a plugin and re-trigger events
---@param pack_spec vim.pack.Spec
---@param bufnr? number
function M.load_and_retrigger(pack_spec, bufnr)
    require("leanpack.loader").load_plugin(pack_spec)
    M.retrigger_events(bufnr or vim.api.nvim_get_current_buf())
end

---Re-trigger events for the current buffer to ensure plugins attach correctly.
---This is a safety net for lazy-loaded plugins that might have missed events.
---@param bufnr number The buffer handle
function M.retrigger_events(bufnr)
    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local events = { "BufReadPre", "BufReadPost", "FileType" }
            for _, event in ipairs(events) do
                vim.api.nvim_exec_autocmds(event, { buffer = bufnr, modeline = false })
            end
        end
    end)
end

return M
