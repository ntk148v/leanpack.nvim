---@module 'tests.hooks_spec'
-- Tests for parcel.hooks module

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
				_G.hooks = require("parcel.hooks")
				_G.state = require("parcel.state")
			]])
		end,
		post_once = child.stop,
	},
})

-- ============================================================================
-- run_init() tests
-- ============================================================================

T["run_init()"] = MiniTest.new_set()

T["run_init()"]["returns false if entry not found"] = function()
	child.lua([[
		_G.result = hooks.run_init("nonexistent")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["run_init()"]["returns true if no init hook"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_init("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["run_init()"]["executes init hook"] = function()
	child.lua([[
		_G.init_called = false
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				init = function() _G.init_called = true end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_init("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.init_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["run_init()"]["handles init hook errors"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				init = function() error("init failed") end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		_G.result = hooks.run_init("test-src")
		
		vim.notify = orig_notify
		_G.has_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("init.*failed") then
				_G.has_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
	MiniTest.expect.equality(child.lua_get("_G.has_error"), true)
end

-- ============================================================================
-- run_config() tests
-- ============================================================================

T["run_config()"] = MiniTest.new_set()

T["run_config()"]["returns false if entry not found"] = function()
	child.lua([[
		_G.result = hooks.run_config("nonexistent")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["run_config()"]["returns true if no config"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_config("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["run_config()"]["executes config function"] = function()
	child.lua([[
		_G.config_called = false
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				config = function() _G.config_called = true end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_config("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.config_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["run_config()"]["resolves opts function"] = function()
	child.lua([[
		_G.opts_resolved = false
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				opts = function(plugin, opts)
					_G.opts_resolved = true
					return { key = "value" }
				end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_config("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.opts_resolved"), true)
end

T["run_config()"]["passes opts to config function"] = function()
	child.lua([[
		_G.received_opts = nil
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				opts = { key = "value" },
				config = function(plugin, opts)
					_G.received_opts = opts
				end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_config("test-src")
	]])

	local opts = child.lua_get("_G.received_opts")
	MiniTest.expect.equality(opts.key, "value")
end

T["run_config()"]["handles config hook errors"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				config = function() error("config failed") end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		
		_G.errors = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then
				table.insert(_G.errors, msg)
			end
		end
		
		_G.result = hooks.run_config("test-src")
		
		vim.notify = orig_notify
		_G.has_error = false
		for _, e in ipairs(_G.errors) do
			if e:match("config.*failed") then
				_G.has_error = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
	MiniTest.expect.equality(child.lua_get("_G.has_error"), true)
end

-- ============================================================================
-- execute_build() tests
-- ============================================================================

T["execute_build()"] = MiniTest.new_set()

T["execute_build()"]["executes string build command"] = function()
	child.lua([[
		_G.command_executed = false
		local orig_cmd = vim.cmd
		vim.cmd = function(cmd)
			if cmd == "echo test" then
				_G.command_executed = true
			else
				orig_cmd(cmd)
			end
		end
		
		local plugin = { spec = { name = "test" }, path = "/tmp/test" }
		hooks.execute_build("echo test", plugin)
		
		vim.cmd = orig_cmd
	]])

	MiniTest.expect.equality(child.lua_get("_G.command_executed"), true)
end

T["execute_build()"]["executes function build"] = function()
	child.lua([[
		_G.build_called = false
		local plugin = { spec = { name = "test" }, path = "/tmp/test" }
		hooks.execute_build(function(p)
			_G.build_called = true
		end, plugin)
	]])

	MiniTest.expect.equality(child.lua_get("_G.build_called"), true)
end

-- ============================================================================
-- run_build() tests
-- ============================================================================

T["run_build()"] = MiniTest.new_set()

T["run_build()"]["returns false if entry not found"] = function()
	child.lua([[
		_G.result = hooks.run_build("nonexistent")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["run_build()"]["returns false if no build hook"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_build("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["run_build()"]["executes build hook"] = function()
	child.lua([[
		_G.build_called = false
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				build = function() _G.build_called = true end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		_G.result = hooks.run_build("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.build_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

-- ============================================================================
-- setup_build_tracking() tests
-- ============================================================================

T["setup_build_tracking()"] = MiniTest.new_set()

T["setup_build_tracking()"]["marks pending build on install"] = function()
	child.lua([[
		hooks.setup_build_tracking()
		
		-- Simulate PackChanged event
		vim.api.nvim_exec_autocmds("PackChanged", {
			data = {
				kind = "install",
				spec = { src = "test-src", name = "test" }
			}
		})
		
		_G.has_pending = state.has_pending_builds()
		_G.pending_src = state.get_pending_builds()["test-src"] ~= nil
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_pending"), true)
	MiniTest.expect.equality(child.lua_get("_G.pending_src"), true)
end

T["setup_build_tracking()"]["marks pending build on update"] = function()
	child.lua([[
		hooks.setup_build_tracking()
		
		-- Simulate PackChanged event
		vim.api.nvim_exec_autocmds("PackChanged", {
			data = {
				kind = "update",
				spec = { src = "test-src", name = "test" }
			}
		})
		
		_G.has_pending = state.has_pending_builds()
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_pending"), true)
end

-- ============================================================================
-- setup_lazy_build_tracking() tests
-- ============================================================================

T["setup_lazy_build_tracking()"] = MiniTest.new_set()

-- ============================================================================
-- run_pending_builds() tests
-- ============================================================================

T["run_pending_builds()"] = MiniTest.new_set()

T["run_pending_builds()"]["returns early if no pending builds"] = function()
	child.lua([[
		_G.builds_run = false
		local orig_execute = hooks.execute_build
		hooks.execute_build = function()
			_G.builds_run = true
		end
		
		hooks.run_pending_builds({})
		
		hooks.execute_build = orig_execute
	]])

	MiniTest.expect.equality(child.lua_get("_G.builds_run"), false)
end

T["run_pending_builds()"]["executes pending builds"] = function()
	child.lua([[
		_G.builds_run = 0
		local orig_execute = hooks.execute_build
		hooks.execute_build = function()
			_G.builds_run = _G.builds_run + 1
		end
		
		state.set_entry("src1", {
			specs = { { src = "src1", name = "test1" } },
			merged_spec = { src = "src1", name = "test1", build = "make" },
			plugin = { spec = { src = "src1", name = "test1" }, path = "/tmp/test1" }
		})
		state.set_entry("src2", {
			specs = { { src = "src2", name = "test2" } },
			merged_spec = { src = "src2", name = "test2", build = "make" },
			plugin = { spec = { src = "src2", name = "test2" }, path = "/tmp/test2" }
		})
		state.register_pack_spec({ src = "src1", name = "test1" })
		state.register_pack_spec({ src = "src2", name = "test2" })
		state.mark_pending_build("src1")
		state.mark_pending_build("src2")
		
		hooks.run_pending_builds({})
		
		hooks.execute_build = orig_execute
	]])

	MiniTest.expect.equality(child.lua_get("_G.builds_run"), 2)
end

T["run_pending_builds()"]["clears pending builds after execution"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test", build = "make" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		state.mark_pending_build("test-src")
		
		_G.has_pending_before = state.has_pending_builds()
		
		local orig_execute = hooks.execute_build
		hooks.execute_build = function() end
		hooks.run_pending_builds({})
		hooks.execute_build = orig_execute
		
		_G.has_pending_after = state.has_pending_builds()
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_pending_before"), true)
	MiniTest.expect.equality(child.lua_get("_G.has_pending_after"), false)
end

-- ============================================================================
-- run_all_builds() tests
-- ============================================================================

T["run_all_builds()"] = MiniTest.new_set()

T["run_all_builds()"]["executes builds for all plugins with build field"] = function()
	child.lua([[
		_G.builds_run = 0
		local orig_execute = hooks.execute_build
		hooks.execute_build = function()
			_G.builds_run = _G.builds_run + 1
		end
		
		state.set_entry("src1", {
			specs = { { src = "src1", name = "test1" } },
			merged_spec = { src = "src1", name = "test1", build = "make" },
			plugin = { spec = { src = "src1", name = "test1" }, path = "/tmp/test1" }
		})
		state.set_entry("src2", {
			specs = { { src = "src2", name = "test2" } },
			merged_spec = { src = "src2", name = "test2", build = "make" },
			plugin = { spec = { src = "src2", name = "test2" }, path = "/tmp/test2" }
		})
		state.set_entry("src3", {
			specs = { { src = "src3", name = "test3" } },
			merged_spec = { src = "src3", name = "test3" },
			plugin = { spec = { src = "src3", name = "test3" }, path = "/tmp/test3" }
		})
		state.register_pack_spec({ src = "src1", name = "test1" })
		state.register_pack_spec({ src = "src2", name = "test2" })
		state.register_pack_spec({ src = "src3", name = "test3" })
		
		hooks.run_all_builds()
		
		hooks.execute_build = orig_execute
	]])

	MiniTest.expect.equality(child.lua_get("_G.builds_run"), 2)
end

T["run_all_builds()"]["sends notification with count"] = function()
	child.lua([[
		_G.notifications = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(_G.notifications, msg)
		end
		
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { src = "test-src", name = "test", build = "make" },
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		state.register_pack_spec({ src = "test-src", name = "test" })
		
		local orig_execute = hooks.execute_build
		hooks.execute_build = function() end
		hooks.run_all_builds()
		hooks.execute_build = orig_execute
		
		vim.notify = orig_notify
		_G.has_count_notification = false
		for _, n in ipairs(_G.notifications) do
			if n:match("1 plugin") then
				_G.has_count_notification = true
				break
			end
		end
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_count_notification"), true)
end

-- ============================================================================
-- Integration tests
-- ============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["complete hook workflow"] = function()
	child.lua([[
		_G.init_called = false
		_G.config_called = false
		_G.build_called = false
		
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				init = function() _G.init_called = true end,
				config = function() _G.config_called = true end,
				build = function() _G.build_called = true end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		
		hooks.run_init("test-src")
		hooks.run_config("test-src")
		hooks.run_build("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.init_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.config_called"), true)
	MiniTest.expect.equality(child.lua_get("_G.build_called"), true)
end

T["integration"]["hooks with opts"] = function()
	child.lua([[
		_G.received_opts = nil
		
		state.set_entry("test-src", {
			specs = { { src = "test-src", name = "test" } },
			merged_spec = { 
				src = "test-src", 
				name = "test",
				opts = { key = "value" },
				config = function(plugin, opts)
					_G.received_opts = opts
				end
			},
			plugin = { spec = { src = "test-src", name = "test" }, path = "/tmp/test" }
		})
		
		hooks.run_config("test-src")
	]])

	local opts = child.lua_get("_G.received_opts")
	MiniTest.expect.equality(opts.key, "value")
end

return T