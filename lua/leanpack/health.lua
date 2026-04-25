---@module 'leanpack.health'
local M = {}

---Health check for leanpack.nvim
function M.check()
    vim.health.start("leanpack.nvim")

    -- Check Neovim version
    if vim.fn.has("nvim-0.12") == 1 then
        vim.health.ok("Neovim 0.12+ detected")
    else
        vim.health.error("leanpack.nvim requires Neovim 0.12+", {
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
    local leanpack_state = require("leanpack.state")

    -- Check for unloaded plugins
    local unloaded = leanpack_state.get_unloaded_names()
    if #unloaded > 0 then
        vim.health.info(("There are %d unloaded plugins"):format(#unloaded))
        for _, name in ipairs(unloaded) do
            vim.health.info(("  - %s"):format(name))
        end
    else
        vim.health.ok("All plugins are loaded")
    end

    -- Check for pending builds
    if leanpack_state.has_pending_builds() then
        local pending = leanpack_state.get_pending_builds()
        vim.health.warn(("There are %d plugins with pending build hooks"):format(vim.tbl_count(pending)), {
            "Run :Leanpack build! to execute all pending build hooks",
        })
    else
        vim.health.ok("No pending build hooks")
    end

    -- Check native lockfile
    local lockfile_path = vim.fn.stdpath("data") .. "/nvim-pack-lock.json"
    if vim.fn.filereadable(lockfile_path) == 1 then
        vim.health.ok(("Native lockfile exists: %s"):format(lockfile_path))
    else
        vim.health.info("No lockfile found. It will be created by vim.pack on first plugin install.")
    end

    -- Bootstrap snippet
    vim.health.start("Bootstrapping")
    vim.health.info("Copy this snippet to the top of your init.lua to automate leanpack.nvim installation:")
    local bootstrap_snippet = [[
local path = vim.fn.stdpath("data") .. "/site/pack/leanpack/opt/leanpack.nvim"
if not (vim.uv or vim.loop).fs_stat(path) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/ntk148v/leanpack.nvim", path })
end
vim.cmd.packadd("leanpack.nvim")
require("leanpack").setup({
  -- your configuration
})]]
    vim.health.info("\n" .. bootstrap_snippet)
end

return M
