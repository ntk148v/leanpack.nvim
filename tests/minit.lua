---@module 'tests.minit'
-- Test bootstrap for leanpack.nvim
-- This file is executed by: nvim -l tests/minit.lua

local M = {}

-- Get the project root directory
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Setup isolated test environment
local test_dir = project_root .. "/.tests"
vim.env.XDG_DATA_HOME = test_dir .. "/data"
vim.env.XDG_STATE_HOME = test_dir .. "/state"
vim.env.XDG_CACHE_HOME = test_dir .. "/cache"
vim.env.XDG_CONFIG_HOME = test_dir .. "/config"

-- Ensure test directories exist
vim.fn.mkdir(test_dir, "p")
vim.fn.mkdir(vim.env.XDG_DATA_HOME, "p")
vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")
vim.fn.mkdir(vim.env.XDG_CACHE_HOME, "p")
vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, "p")

-- Prepend project root to runtimepath
vim.opt.rtp:prepend(project_root)

-- Bootstrap mini.test if not present
local mini_test_path = vim.env.XDG_DATA_HOME .. "/site/pack/test/start/mini.test"
if vim.fn.isdirectory(mini_test_path) == 0 then
    print("Bootstrapping mini.test...")
    vim.fn.mkdir(mini_test_path, "p")
    local clone_cmd = {
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/echasnovski/mini.test",
        mini_test_path,
    }
    local result = vim.fn.system(clone_cmd)
    if vim.v.shell_error ~= 0 then
        error("Failed to clone mini.test: " .. result)
    end
    print("mini.test installed successfully")
end

-- Bootstrap mini.nvim (dependency for mini.test)
local mini_deps_path = vim.env.XDG_DATA_HOME .. "/site/pack/test/start/mini.nvim"
if vim.fn.isdirectory(mini_deps_path) == 0 then
    print("Bootstrapping mini.nvim...")
    vim.fn.mkdir(mini_deps_path, "p")
    local clone_cmd = {
        "git",
        "--git-dir=/dev/null",
        "clone",
        "--filter=blob:none",
        "https://github.com/echasnovski/mini.nvim",
        mini_deps_path,
    }
    local result = vim.fn.system(clone_cmd)
    if vim.v.shell_error ~= 0 then
        error("Failed to clone mini.nvim: " .. result)
    end
    print("mini.nvim installed successfully")
end

-- Add mini.test to runtimepath
vim.opt.rtp:prepend(mini_test_path)

-- Setup mini.test
local MiniTest = require("mini.test")

-- Configure mini.test
MiniTest.setup({
    collect = {
        -- Find all *_spec.lua files in tests/ directory
        find_files = function()
            local test_files = {}
            local scan = vim.loop.fs_scandir(project_root .. "/tests")
            if scan then
                while true do
                    local name, type = vim.loop.fs_scandir_next(scan)
                    if not name then
                        break
                    end
                    if type == "file" and name:match("_spec%.lua$") then
                        table.insert(test_files, project_root .. "/tests/" .. name)
                    end
                end
            end
            return test_files
        end,
    },
    reporter = {
        -- Use default reporter with custom output
        serialize = function(x)
            return vim.inspect(x, { newline = "", indent = "" })
        end,
    },
    execute = {
        -- Stop on first error for faster feedback during development
        stop_on_error = false,
    },
})

-- Global test helpers
_G.TestHelpers = require("tests.helpers")

-- Parse command line arguments
-- Look for arguments after minit.lua
local args = {}
local found_minit = false
for i = 1, #vim.v.argv do
    local arg = vim.v.argv[i]
    if found_minit and not arg:match("^-") then
        -- Collect non-flag arguments after minit.lua
        table.insert(args, arg)
    elseif arg:match("minit%.lua$") then
        found_minit = true
    end
end

-- Filter tests if pattern provided
local test_pattern = args[1]
if test_pattern then
    print("Running tests matching pattern: " .. test_pattern)
    -- Override find_files to filter by pattern
    MiniTest.config.collect.find_files = function()
        local test_files = {}
        local scan = vim.loop.fs_scandir(project_root .. "/tests")
        if scan then
            while true do
                local name, type = vim.loop.fs_scandir_next(scan)
                if not name then
                    break
                end
                if type == "file" and name:match("_spec%.lua$") and name:match(test_pattern) then
                    table.insert(test_files, project_root .. "/tests/" .. name)
                end
            end
        end
        return test_files
    end
end

-- Run tests
print("\n" .. string.rep("=", 60))
print("Running leanpack.nvim tests")
print(string.rep("=", 60) .. "\n")

local success = MiniTest.run()

-- mini.test output format:
-- 'o' = passed, 'x' = failed
-- Final line shows "Fails (N) and Notes (M)"

-- Exit with appropriate code
if success then
    vim.cmd("quit 0")
else
    vim.cmd("quit 1")
end
