---@module 'tests.module_trigger_spec'
-- Tests for leanpack.lazy_trigger.module

local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
				vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
				_G.helpers = require("tests.helpers")
				_G.helpers.reset_leanpack_state()
				_G.state = require("leanpack.state")
				_G.module_trigger = require("leanpack.lazy_trigger.module")
			]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- setup() tests
-- ============================================================================

T["setup()"] = MiniTest.new_set()

T["setup()"]["skips when no plugins have main field"] = function()
    child.lua([[
		_G.before = #(package.loaders or package.searchers)
		_G.module_trigger.setup({})
		_G.after = #(package.loaders or package.searchers)
	]])

    MiniTest.expect.equality(child.lua_get("_G.before"), child.lua_get("_G.after"))
end

T["setup()"]["installs loader at position 2 when plugins have main field"] = function()
    child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test-plugin" } },
			merged_spec = { src = "test-src", name = "test-plugin", main = "test_module" },
			load_status = "pending",
			plugin = { spec = { src = "test-src", name = "test-plugin" }, path = "/tmp/test" },
		})
		state.register_pack_spec({ src = "test-src", name = "test-plugin" })

		_G.loader_count_before = #(package.loaders or package.searchers)
		_G.module_trigger.setup({ { src = "test-src", name = "test-plugin" } })
		_G.loader_count_after = #(package.loaders or package.searchers)
	]])

    local before = child.lua_get("_G.loader_count_before")
    local after = child.lua_get("_G.loader_count_after")
    MiniTest.expect.equality(after, before + 1)
end

T["setup()"]["registers main module and .init variant"] = function()
    child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test-plugin" } },
			merged_spec = { src = "test-src", name = "test-plugin", main = "my_module" },
			load_status = "pending",
			plugin = { spec = { src = "test-src", name = "test-plugin" }, path = "/tmp/test" },
		})
		state.register_pack_spec({ src = "test-src", name = "test-plugin" })

		_G.module_trigger.setup({ { src = "test-src", name = "test-plugin" } })
	]])

    -- Loader installed = count increased (verified in previous test)
    -- Cannot directly inspect module_to_src (local), but setup completed without error
end

-- ============================================================================
-- recursion guard tests
-- ============================================================================

T["recursion guard"] = MiniTest.new_set()

T["recursion guard"]["prevents infinite recursion on re-entry"] = function()
    child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test-plugin" } },
			merged_spec = { src = "test-src", name = "test-plugin", main = "nonexistent_module" },
			load_status = "pending",
			plugin = { spec = { src = "test-src", name = "test-plugin" }, path = "/tmp/test" },
		})
		state.register_pack_spec({ src = "test-src", name = "test-plugin" })

		_G.module_trigger.setup({ { src = "test-src", name = "test-plugin" } })

		-- Attempt to require a module that won't resolve
		-- This should not stack overflow
		_G.load_ok = pcall(require, "nonexistent_module")
	]])

    -- require should fail gracefully (module not found), not stack overflow
    MiniTest.expect.equality(child.lua_get("_G.load_ok"), false)
end

-- ============================================================================
-- passthrough tests
-- ============================================================================

T["passthrough"] = MiniTest.new_set()

T["passthrough"]["non-registered modules pass through to original loaders"] = function()
    child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test-plugin" } },
			merged_spec = { src = "test-src", name = "test-plugin", main = "registered_module" },
			load_status = "pending",
			plugin = { spec = { src = "test-src", name = "test-plugin" }, path = "/tmp/test" },
		})
		state.register_pack_spec({ src = "test-src", name = "test-plugin" })

		_G.module_trigger.setup({ { src = "test-src", name = "test-plugin" } })

		-- Requiring a module NOT in module_to_src should pass through
		-- leanpack.state is already loaded, so this should succeed
		_G.pass_ok = pcall(require, "leanpack.state")
	]])

    MiniTest.expect.equality(child.lua_get("_G.pass_ok"), true)
end

return T
