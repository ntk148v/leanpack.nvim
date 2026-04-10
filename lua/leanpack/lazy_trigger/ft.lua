---@module 'leanpack.lazy_trigger.ft'
local state = require("leanpack.state")
local loader = require("leanpack.loader")
local spec_mod = require("leanpack.spec")

local M = {}

---Setup filetype-based lazy loading
---@param pack_spec vim.pack.Spec
---@param ft leanpack.FtValue
function M.setup(pack_spec, ft)
  local filetypes = spec_mod.normalize_list(ft) or {}

  vim.api.nvim_create_autocmd("FileType", {
    group = state.lazy_group,
    pattern = filetypes,
    once = true,
    callback = function(ev)
      loader.load_plugin(pack_spec)
      require("leanpack.lazy_trigger.util").retrigger_events(ev.buf)
    end,
  })
end

return M