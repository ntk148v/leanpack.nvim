---@module 'tests.test_main_detection'
-- Tests for automatic main module detection

local MiniTest = require("mini.test")
local helpers = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
        vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
        _G.helpers = require("tests.helpers")
        _G.helpers.reset_leanpack_state()
        _G.spec_mod = require("leanpack.spec")
      ]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- normname() tests
-- ============================================================================

T["normname()"] = MiniTest.new_set()

T["normname()"]["strips nvim prefix and suffix"] = function()
    child.lua([[
    _G.result = spec_mod.normname("nvim-cmp")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "cmp")
end

T["normname()"]["strips .nvim suffix"] = function()
    child.lua([[
    _G.result = spec_mod.normname("telescope.nvim")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "telescope")
end

T["normname()"]["strips vim prefix"] = function()
    child.lua([[
    _G.result = spec_mod.normname("vim-test")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "test")
end

T["normname()"]["handles none-ls.nvim"] = function()
    child.lua([[
    _G.result = spec_mod.normname("none-ls.nvim")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "nonels")
end

T["normname()"]["handles null-ls"] = function()
    child.lua([[
    _G.result = spec_mod.normname("null-ls")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "nullls")
end

-- ============================================================================
-- detect_main() tests
-- ============================================================================

T["detect_main()"] = MiniTest.new_set()

T["detect_main()"]["detects null-ls for none-ls.nvim"] = function()
    child.lua([[
    local path = vim.fn.expand("~/.local/share/nvim-lazy/lazy/none-ls.nvim")
    if vim.fn.isdirectory(path) == 1 then
      _G.result = spec_mod.detect_main("none-ls.nvim", path)
    else
      _G.result = nil
    end
  ]])
    local result = child.lua_get("_G.result")
    -- Only test if none-ls.nvim is installed
    if result ~= nil then
        MiniTest.expect.equality(result, "null-ls")
    end
end

T["detect_main()"]["returns nil for non-existent directory"] = function()
    child.lua([[
    _G.result = spec_mod.detect_main("test-plugin", "/nonexistent/path")
  ]])
    local result = child.lua_get("_G.result")
    -- nil is returned as vim.NIL when crossing the child boundary
    MiniTest.expect.equality(result == nil or result == vim.NIL, true)
end

T["detect_main()"]["detects main module with init.lua"] = function()
    child.lua([[
    local test_dir = os.tmpname()
    os.remove(test_dir)
    vim.fn.mkdir(test_dir, "p")
    local lua_dir = test_dir .. "/lua"
    vim.fn.mkdir(lua_dir, "p")
    vim.fn.mkdir(lua_dir .. "/myplugin", "p")

    local f = io.open(lua_dir .. "/myplugin/init.lua", "w")
    f:write("return {}")
    f:close()

    _G.result = spec_mod.detect_main("myplugin.nvim", test_dir)
    _G.test_dir = test_dir

    -- Cleanup in child
    vim.fn.delete(test_dir, "rf")
  ]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, "myplugin")
end

return T
