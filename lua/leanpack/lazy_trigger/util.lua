---@module 'leanpack.lazy_trigger.util'
local M = {}

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
