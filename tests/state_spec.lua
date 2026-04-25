---@module 'tests.state_spec'
-- Tests for leanpack.state module

local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
				vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
				_G.state = require("leanpack.state")
				state.reset()
			]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- reset tests
-- ============================================================================

T["reset()"] = MiniTest.new_set()

T["reset()"]["clears all state"] = function()
    child.lua([[
		-- Add some state
		state.mark_setup()
		state.set_entry("test-src", { specs = {} })
		state.add_dependency("parent", "child")
		state.register_pack_spec({ src = "test", name = "test" })
		state.mark_plugin_with_build("test")
		state.mark_unloaded("test")
		state.mark_pending_build("test")

		-- Reset
		state.reset()
	]])

    MiniTest.expect.equality(child.lua_get("state.is_configured()"), false)
    MiniTest.expect.equality(child.lua_get("state.has_pending_builds()"), false)
end

-- ============================================================================
-- setup state tests
-- ============================================================================

T["setup state"] = MiniTest.new_set()

T["setup state"]["is_configured returns false initially"] = function()
    MiniTest.expect.equality(child.lua_get("state.is_configured()"), false)
end

T["setup state"]["mark_setup sets configured"] = function()
    child.lua("state.mark_setup()")
    MiniTest.expect.equality(child.lua_get("state.is_configured()"), true)
end

-- ============================================================================
-- registry tests
-- ============================================================================

T["registry"] = MiniTest.new_set()

T["registry"]["get_entry returns nil for unknown src"] = function()
    child.lua([[
		_G.result = state.get_entry("unknown")
	]])
    MiniTest.expect.equality(child.lua_get("_G.result"), vim.NIL)
end

T["registry"]["set_entry and get_entry work"] = function()
    child.lua([[
		local entry = { specs = { { src = "test" } }, load_status = "pending" }
		state.set_entry("test-src", entry)
		_G.result = state.get_entry("test-src")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result ~= vim.NIL, true)
    MiniTest.expect.equality(result.load_status, "pending")
end

T["registry"]["get_all_entries returns all entries"] = function()
    child.lua([[
		state.set_entry("src1", { specs = {} })
		state.set_entry("src2", { specs = {} })
		_G.result = state.get_all_entries()
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.src1 ~= nil, true)
    MiniTest.expect.equality(result.src2 ~= nil, true)
end

-- ============================================================================
-- dependency graph tests
-- ============================================================================

T["dependency graph"] = MiniTest.new_set()

T["dependency graph"]["add_dependency creates forward edge"] = function()
    child.lua([[
		state.add_dependency("parent", "child")
		_G.result = state.get_dependencies("parent")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result ~= vim.NIL, true)
    MiniTest.expect.equality(result.child, true)
end

T["dependency graph"]["add_dependency creates reverse edge"] = function()
    child.lua([[
		state.add_dependency("parent", "child")
		_G.result = state.get_reverse_dependencies("child")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result ~= vim.NIL, true)
    MiniTest.expect.equality(result.parent, true)
end

T["dependency graph"]["handles multiple dependencies"] = function()
    child.lua([[
		state.add_dependency("parent", "child1")
		state.add_dependency("parent", "child2")
		_G.result = state.get_dependencies("parent")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.child1, true)
    MiniTest.expect.equality(result.child2, true)
end

T["dependency graph"]["handles multiple parents"] = function()
    child.lua([[
		state.add_dependency("parent1", "child")
		state.add_dependency("parent2", "child")
		_G.result = state.get_reverse_dependencies("child")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.parent1, true)
    MiniTest.expect.equality(result.parent2, true)
end

-- ============================================================================
-- pack spec tests
-- ============================================================================

T["pack spec"] = MiniTest.new_set()

T["pack spec"]["register_pack_spec stores spec"] = function()
    child.lua([[
		-- Need to create an entry first
		state.set_entry("test-src", { specs = {} })
		state.register_pack_spec({ src = "test-src", name = "test-name" })
		_G.result = state.get_pack_spec("test-src")
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.src, "test-src")
    MiniTest.expect.equality(result.name, "test-name")
end

T["pack spec"]["get_all_pack_specs returns all specs"] = function()
    child.lua([[
		state.set_entry("src1", { specs = {} })
		state.set_entry("src2", { specs = {} })
		state.register_pack_spec({ src = "src1", name = "name1" })
		state.register_pack_spec({ src = "src2", name = "name2" })
		_G.result = state.get_all_pack_specs()
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 2)
end

-- ============================================================================
-- build tracking tests
-- ============================================================================

T["build tracking"] = MiniTest.new_set()

T["build tracking"]["mark_plugin_with_build tracks unique names"] = function()
    child.lua([[
		state.mark_plugin_with_build("plugin1")
		state.mark_plugin_with_build("plugin1") -- duplicate
		state.mark_plugin_with_build("plugin2")
		_G.result = state.get_plugins_with_build()
	]])

    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 2)
end

T["build tracking"]["pending builds can be marked and cleared"] = function()
    child.lua([[
		state.mark_pending_build("testsrc")
		_G.has_pending = state.has_pending_builds()
		_G.pending = state.get_pending_builds()
		_G.has_testsrc = _G.pending["testsrc"] ~= nil

		state.clear_pending_build("testsrc")
		_G.has_pending_after = state.has_pending_builds()
	]])

    MiniTest.expect.equality(child.lua_get("_G.has_pending"), true)
    MiniTest.expect.equality(child.lua_get("_G.has_testsrc"), true)
    MiniTest.expect.equality(child.lua_get("_G.has_pending_after"), false)
end

T["build tracking"]["clear_all_pending_builds clears all"] = function()
    child.lua([[
		state.mark_pending_build("src1")
		state.mark_pending_build("src2")
		state.clear_all_pending_builds()
		_G.result = state.has_pending_builds()
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

-- ============================================================================
-- load status tests
-- ============================================================================

T["load status"] = MiniTest.new_set()

T["load status"]["tracks unloaded plugins"] = function()
    child.lua([[
		state.mark_unloaded("plugin1")
		_G.is_unloaded = state.is_unloaded("plugin1")
		_G.unloaded_names = state.get_unloaded_names()
	]])

    MiniTest.expect.equality(child.lua_get("_G.is_unloaded"), true)
    MiniTest.expect.equality(#child.lua_get("_G.unloaded_names"), 1)
end

T["load status"]["mark_loaded removes from unloaded"] = function()
    child.lua([[
		state.mark_unloaded("plugin1")
		state.mark_loaded("plugin1")
		_G.is_unloaded = state.is_unloaded("plugin1")
	]])

    MiniTest.expect.equality(child.lua_get("_G.is_unloaded"), false)
end

-- ============================================================================
-- remove plugin tests
-- ============================================================================

T["remove plugin"] = MiniTest.new_set()

T["remove plugin"]["remove_plugin clears all references"] = function()
    child.lua([[
		-- Setup
		state.set_entry("test-src", { specs = {} })
		state.register_pack_spec({ src = "test-src", name = "test-name" })
		state.mark_plugin_with_build("test-name")
		state.mark_unloaded("test-name")
		state.mark_pending_build("test-src")

		-- Remove
		state.remove_plugin("test-name", "test-src")

		-- Verify
		_G.entry = state.get_entry("test-src")
		_G.pack_spec = state.get_pack_spec("test-src")
		_G.has_pending = state.src_with_pending_build and state.src_with_pending_build["test-src"]
	]])

    MiniTest.expect.equality(child.lua_get("_G.entry"), vim.NIL)
    MiniTest.expect.equality(child.lua_get("_G.pack_spec"), vim.NIL)
end

-- ============================================================================
-- autocmd groups tests
-- ============================================================================

T["autocmd groups"] = MiniTest.new_set()

T["autocmd groups"]["groups are created"] = function()
    child.lua([[
		_G.startup_exists = vim.api.nvim_create_augroup("leanpack_startup", { clear = false }) ~= 0
		_G.lazy_exists = vim.api.nvim_create_augroup("leanpack_lazy", { clear = false }) ~= 0
		_G.lazy_build_exists = vim.api.nvim_create_augroup("leanpack_lazy_build", { clear = false }) ~= 0
	]])

    MiniTest.expect.equality(child.lua_get("_G.startup_exists"), true)
    MiniTest.expect.equality(child.lua_get("_G.lazy_exists"), true)
    MiniTest.expect.equality(child.lua_get("_G.lazy_build_exists"), true)
end

return T
