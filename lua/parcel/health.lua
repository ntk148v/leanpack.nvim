---@module 'parcel.health'
local M = {}

---Health check for parcel.nvim
function M.check()
  vim.health.start("parcel.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim 0.12+ detected")
  else
    vim.health.error("parcel.nvim requires Neovim 0.12+", {
      "Upgrade to Neovim 0.12 or later",
    })
  end

  -- Check if vim.pack is available
  if vim.pack and vim.pack.add then
    vim.health.ok("vim.pack module is available")
  else
    vim.health.error("vim.pack module not found", {
      "Ensure you're running Neovim 0.12+",
    })
  end

  -- Check git
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git is available")
  else
    vim.health.warn("git not found", {
      "vim.pack requires git for plugin management",
    })
  end

  -- Check for common issues
  local state = require("parcel.state")

  -- Check for unloaded plugins
  local unloaded = state.get_unloaded_names()
  if #unloaded > 0 then
    vim.health.info(("There are %d unloaded plugins"):format(#unloaded))
    for _, name in ipairs(unloaded) do
      vim.health.info(("  - %s"):format(name))
    end
  else
    vim.health.ok("All plugins are loaded")
  end

  -- Check for pending builds
  if state.has_pending_builds() then
    local pending = state.get_pending_builds()
    vim.health.warn(("There are %d plugins with pending build hooks"):format(vim.tbl_count(pending)), {
      "Run :PBuild! to execute all pending build hooks",
    })
  else
    vim.health.ok("No pending build hooks")
  end

  -- Check lockfile
  local lockfile = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
  if vim.fn.filereadable(lockfile) == 1 then
    vim.health.ok("Lockfile exists: " .. lockfile)
  else
    vim.health.info("No lockfile found. It will be created on first plugin install.")
  end
end

return M