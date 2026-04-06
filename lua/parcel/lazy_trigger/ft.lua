---@module 'parcel.lazy_trigger.ft'
local state = require("parcel.state")
local loader = require("parcel.loader")
local spec_mod = require("parcel.spec")

local M = {}

---Setup filetype-based lazy loading
---@param pack_spec vim.pack.Spec
---@param ft parcel.FtValue
function M.setup(pack_spec, ft)
  local filetypes = spec_mod.normalize_list(ft) or {}

  vim.api.nvim_create_autocmd("FileType", {
    group = state.lazy_group,
    pattern = filetypes,
    once = true,
    callback = function(ev)
      loader.load_plugin(pack_spec)

      -- Re-trigger events for the buffer to ensure LSP/Treesitter attach
      vim.schedule(function()
        local bufnr = ev.buf
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })
          vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
          vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
        end
      end)
    end,
  })
end

return M