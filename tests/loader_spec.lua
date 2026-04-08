---@module 'tests.loader_spec'
-- Tests for parcel.loader module

local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "NONE" })
			child.lua([[
				vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
				_G.helpers = require("tests.helpers")
				_G.helpers.reset_parcel_state()
				_G.loader = require("parcel.loader")
				_G.state = require("parcel.state")
				_G.spec_mod = require("parcel.spec")
			]])
		end,
		post_once = child.stop,
	},
})

-- ============================================================================
-- load_plugin() tests
-- ============================================================================

T["load_plugin()"] = MiniTest.new_set()

T["load_plugin()"]["returns early if plugin not in registry"] = function()
	child.lua([[
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		loader.load_plugin({ src = "unknown", name = "unknown" })
		
		vim.notify = orig_notify
		_G.has_error = #_G.errors > 0
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_error"), true)
end

T["load_plugin()"]["returns early if already loaded"] = function()
	child.lua([[
		-- Setup a plugin
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			load_status = "loaded"
		})
		
		_G.loaded_before = state.get_entry("test-src").load_status
		loader.load_plugin({ src = "test-src", name = "test" })
		_G.loaded_after = state.get_entry("test-src").load_status
	]])

	MiniTest.expect.equality(child.lua_get("_G.loaded_before"), "loaded")
	MiniTest.expect.equality(child.lua_get("_G.loaded_after"), "loaded")
end

T["load_plugin()"]["detects circular dependencies"] = function()
	child.lua([[
		-- Setup circular dependency
		state.set_entry("a", {
			specs = { { src = "a", name = "a" } },
			merged_spec = { src = "a", name = "a" },
			load_status = "loading"
		})
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		loader.load_plugin({ src = "a", name = "a" })
		
		vim.notify = orig_notify
		_G.has_circular_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("Circular") then
				_G.has_circular_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_circular_error"), true)
end

T["load_plugin()"]["loads dependencies first"] = function()
	child.lua([[
		-- Setup parent with dependency
		state.set_entry("parent", {
			specs = { { src = "parent", name = "parent" } },
			merged_spec = { src = "parent", name = "parent" },
			plugin = { spec = { src = "parent", name = "parent" }, path = "/tmp/parent" },
			load_status = "pending"
		})
		state.set_entry("child", {
			specs = { { src = "child", name = "child" } },
			merged_spec = { src = "child", name = "child" },
			plugin = { spec = { src = "child", name = "child" }, path = "/tmp/child" },
			load_status = "pending"
		})
		state.add_dependency("parent", "child")
		state.register_pack_spec({ src = "parent", name = "parent" })
		state.register_pack_spec({ src = "child", name = "child" })
		
		_G.child_loaded_before = state.get_entry("child").load_status
		loader.load_plugin({ src = "parent", name = "parent" })
		_G.child_loaded_after = state.get_entry("child").load_status
	]])

	MiniTest.expect.equality(child.lua_get("_G.child_loaded_before"), "pending")
	MiniTest.expect.equality(child.lua_get("_G.child_loaded_after"), "loaded")
end

T["load_plugin()"]["warns about missing optional dependencies"] = function()
	child.lua([[
		-- Setup parent with optional dependency
		state.set_entry("parent", {
			specs = { { src = "parent", name = "parent" } },
			merged_spec = { src = "parent", name = "parent" },
			load_status = "pending"
		})
		-- Set up the missing dependency in registry but don't register its pack spec
		state.set_entry("missing", {
			specs = { { src = "missing", name = "missing", optional = true } },
			merged_spec = { src = "missing", name = "missing", optional = true },
			load_status = "pending"
		})
		state.add_dependency("parent", "missing")
		state.register_pack_spec({ src = "parent", name = "parent" })
		
		_G.warnings = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN then
				table.insert(_G.warnings, msg)
			end
		end
		
		loader.load_plugin({ src = "parent", name = "parent" })
		
		vim.notify = orig_notify
		_G.has_optional_warning = false
		for _, w in ipairs(_G.warnings) do
			if w:match("Optional") then
				_G.has_optional_warning = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_optional_warning"), true)
end

T["load_plugin()"]["errors on missing required dependencies"] = function()
	child.lua([[
		-- Setup parent with required dependency
		state.set_entry("parent", {
			specs = { { src = "parent", name = "parent" } },
			merged_spec = { src = "parent", name = "parent" },
			load_status = "pending"
		})
		-- Set up the missing dependency in registry but don't register its pack spec
		state.set_entry("missing", {
			specs = { { src = "missing", name = "missing" } },
			merged_spec = { src = "missing", name = "missing" },
			load_status = "pending"
		})
		state.add_dependency("parent", "missing")
		state.register_pack_spec({ src = "parent", name = "parent" })
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		loader.load_plugin({ src = "parent", name = "parent" })
		
		vim.notify = orig_notify
		_G.has_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("Dependency.*not found") then
				_G.has_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_error"), true)
end

T["load_plugin()"]["marks plugin as loaded"] = function()
	child.lua([[
		-- Setup a plugin
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" },
			load_status = "pending"
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		
		_G.loaded_before = state.get_entry("test-src").load_status
		loader.load_plugin({ src = "test-src", name = "test" })
		_G.loaded_after = state.get_entry("test-src").load_status
		_G.is_loaded = not state.is_unloaded("test")
	]])

	MiniTest.expect.equality(child.lua_get("_G.loaded_before"), "pending")
	MiniTest.expect.equality(child.lua_get("_G.loaded_after"), "loaded")
	MiniTest.expect.equality(child.lua_get("_G.is_loaded"), true)
end

-- ============================================================================
-- process_startup() tests
-- ============================================================================

T["process_startup()"] = MiniTest.new_set()

T["process_startup()"]["runs init hooks in priority order"] = function()
	child.lua([[
		_G.init_order = {}
		
		state.set_entry("low", {
			specs = { { src = "low", name = "low", priority = 10, init = function() table.insert(_G.init_order, "low") end } },
			merged_spec = { src = "low", name = "low", priority = 10, init = function() table.insert(_G.init_order, "low") end },
			load_status = "pending"
		})
		state.set_entry("high", {
			specs = { { src = "high", name = "high", priority = 100, init = function() table.insert(_G.init_order, "high") end } },
			merged_spec = { src = "high", name = "high", priority = 100, init = function() table.insert(_G.init_order, "high") end },
			load_status = "pending"
		})
		
		local ctx = {
			srcs_with_init = { "low", "high" },
			startup_packs = {
				{ src = "low", name = "low" },
				{ src = "high", name = "high" }
			}
		}
		
		loader.process_startup(ctx)
	]])

	local init_order = child.lua_get("_G.init_order")
	MiniTest.expect.equality(init_order[1], "high")
	MiniTest.expect.equality(init_order[2], "low")
end

T["process_startup()"]["loads plugins in dependency order"] = function()
	child.lua([[
		-- Setup: parent depends on child
		state.set_entry("parent", {
			specs = { { src = "parent", name = "parent", priority = 50 } },
			merged_spec = { src = "parent", name = "parent", priority = 50 },
			plugin = { spec = { src = "parent", name = "parent" }, path = "/tmp/parent" },
			load_status = "pending"
		})
		state.set_entry("child", {
			specs = { { src = "child", name = "child", priority = 50 } },
			merged_spec = { src = "child", name = "child", priority = 50 },
			plugin = { spec = { src = "child", name = "child" }, path = "/tmp/child" },
			load_status = "pending"
		})
		state.add_dependency("parent", "child")
		state.register_pack_spec({ src = "parent", name = "parent" })
		state.register_pack_spec({ src = "child", name = "child" })
		
		local ctx = {
			srcs_with_init = {},
			startup_packs = {
				{ src = "parent", name = "parent" },
				{ src = "child", name = "child" }
			}
		}
		
		_G.child_loaded_before = state.get_entry("child").load_status
		loader.process_startup(ctx)
		_G.child_loaded_after = state.get_entry("child").load_status
	]])

	MiniTest.expect.equality(child.lua_get("_G.child_loaded_before"), "pending")
	MiniTest.expect.equality(child.lua_get("_G.child_loaded_after"), "loaded")
end

T["process_startup()"]["marks all startup plugins as loaded"] = function()
	child.lua([[
		state.set_entry("plugin1", {
			specs = { { src = "plugin1", name = "plugin1" } },
			merged_spec = { src = "plugin1", name = "plugin1" },
			plugin = { spec = { src = "plugin1", name = "plugin1" }, path = "/tmp/plugin1" },
			load_status = "pending"
		})
		state.set_entry("plugin2", {
			specs = { { src = "plugin2", name = "plugin2" } },
			merged_spec = { src = "plugin2", name = "plugin2" },
			plugin = { spec = { src = "plugin2", name = "plugin2" }, path = "/tmp/plugin2" },
			load_status = "pending"
		})
		state.register_pack_spec({ src = "plugin1", name = "plugin1" })
		state.register_pack_spec({ src = "plugin2", name = "plugin2" })
		
		local ctx = {
			srcs_with_init = {},
			startup_packs = {
				{ src = "plugin1", name = "plugin1" },
				{ src = "plugin2", name = "plugin2" }
			}
		}
		
		loader.process_startup(ctx)
		_G.p1_loaded = state.get_entry("plugin1").load_status
		_G.p2_loaded = state.get_entry("plugin2").load_status
	]])

	MiniTest.expect.equality(child.lua_get("_G.p1_loaded"), "loaded")
	MiniTest.expect.equality(child.lua_get("_G.p2_loaded"), "loaded")
end

-- ============================================================================
-- Error handling tests
-- ============================================================================

T["error handling"] = MiniTest.new_set()

T["error handling"]["handles missing plugin object"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			load_status = "pending"
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		loader.load_plugin({ src = "test-src", name = "test" })
		
		vim.notify = orig_notify
		_G.has_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("plugin not registered") then
				_G.has_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_error"), true)
end

T["error handling"]["handles failed config hook"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				config = function() error("config failed") end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" },
			load_status = "pending"
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		loader.load_plugin({ src = "test-src", name = "test" })
		
		vim.notify = orig_notify
		_G.has_config_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("config.*failed") then
				_G.has_config_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_config_error"), true)
end

-- ============================================================================
-- Integration tests
-- ============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["loads plugin with config and keymaps"] = function()
	child.lua([[
		_G.config_called = false
		_G.keys_applied = false
		
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				config = function() _G.config_called = true end,
				keys = "<leader>t"
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" },
			load_status = "pending"
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		
		loader.load_plugin({ src = "test-src", name = "test" })
	]])

	MiniTest.expect.equality(child.lua_get("_G.config_called"), true)
end

T["integration"]["handles complex dependency graph"] = function()
	child.lua([[
		-- Setup: a -> b -> c, a -> d
		state.set_entry("a", {
			specs = { { src = "a", name = "a" } },
			merged_spec = { src = "a", name = "a" },
			plugin = { spec = { src = "a", name = "a" }, path = "/tmp/a" },
			load_status = "pending"
		})
		state.set_entry("b", {
			specs = { { src = "b", name = "b" } },
			merged_spec = { src = "b", name = "b" },
			plugin = { spec = { src = "b", name = "b" }, path = "/tmp/b" },
			load_status = "pending"
		})
		state.set_entry("c", {
			specs = { { src = "c", name = "c" } },
			merged_spec = { src = "c", name = "c" },
			plugin = { spec = { src = "c", name = "c" }, path = "/tmp/c" },
			load_status = "pending"
		})
		state.set_entry("d", {
			specs = { { src = "d", name = "d" } },
			merged_spec = { src = "d", name = "d" },
			plugin = { spec = { src = "d", name = "d" }, path = "/tmp/d" },
			load_status = "pending"
		})
		state.add_dependency("a", "b")
		state.add_dependency("b", "c")
		state.add_dependency("a", "d")
		state.register_pack_spec({ src = "a", name = "a" })
		state.register_pack_spec({ src = "b", name = "b" })
		state.register_pack_spec({ src = "c", name = "c" })
		state.register_pack_spec({ src = "d", name = "d" })
		
		loader.load_plugin({ src = "a", name = "a" })
		
		_G.all_loaded = (
			state.get_entry("a").load_status == "loaded" and
			state.get_entry("b").load_status == "loaded" and
			state.get_entry("c").load_status == "loaded" and
			state.get_entry("d").load_status == "loaded"
		)
	]])

	MiniTest.expect.equality(child.lua_get("_G.all_loaded"), true)
end

T["integration"]["loads dependencies before config runs"] = function()
	child.lua([[
		-- Simulate nvim-lspconfig depending on cmp-nvim-lsp
		-- Plugin A (nvim-lspconfig) depends on Plugin B (cmp-nvim-lsp)
		-- Plugin A's config requires Plugin B's module
		
		_G.load_order = {}
		
		state.set_entry("plugin-a", {
			specs = { { src = "plugin-a", name = "plugin-a", dependencies = { "plugin-b" } } },
			merged_spec = { 
				src = "plugin-a", 
				name = "plugin-a",
				dependencies = { "plugin-b" },
				config = function() 
					-- Simulate requiring plugin-b's module
					_G.config_a_called = true
					-- Check if plugin-b is loaded before this config runs
					_G.plugin_b_loaded_before_config_a = state.get_entry("plugin-b").load_status == "loaded"
				end
			},
			plugin = { spec = { src = "plugin-a", name = "plugin-a" }, path = "/tmp/plugin-a" },
			load_status = "pending"
		})
		state.set_entry("plugin-b", {
			specs = { { src = "plugin-b", name = "plugin-b" } },
			merged_spec = { src = "plugin-b", name = "plugin-b" },
			plugin = { spec = { src = "plugin-b", name = "plugin-b" }, path = "/tmp/plugin-b" },
			load_status = "pending"
		})
		state.add_dependency("plugin-a", "plugin-b")
		state.register_pack_spec({ src = "plugin-a", name = "plugin-a" })
		state.register_pack_spec({ src = "plugin-b", name = "plugin-b" })
		
		loader.load_plugin({ src = "plugin-a", name = "plugin-a" })
		
		_G.all_loaded = (
			state.get_entry("plugin-a").load_status == "loaded" and
			state.get_entry("plugin-b").load_status == "loaded"
		)
	]])

MiniTest.expect.equality(child.lua_get("_G.all_loaded"), true)
	MiniTest.expect.equality(child.lua_get("_G.config_a_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.plugin_b_loaded_before_config_a"), true)
end

	return T