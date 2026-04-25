---@module 'tests.lazy_spec'
-- Tests for leanpack.lazy module and lazy loading triggers

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
				_G.lazy = require("leanpack.lazy")
				_G.spec_mod = require("leanpack.spec")
				_G.state = require("leanpack.state")
			]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- is_lazy tests
-- ============================================================================

T["is_lazy()"] = MiniTest.new_set()

T["is_lazy()"]["returns explicit lazy flag"] = function()
    child.lua([[
		_G.result_true = lazy.is_lazy({ lazy = true })
		_G.result_false = lazy.is_lazy({ lazy = false })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result_true"), true)
    MiniTest.expect.equality(child.lua_get("_G.result_false"), false)
end

T["is_lazy()"]["detects event trigger"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ event = "BufRead" })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_lazy()"]["detects cmd trigger"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ cmd = "MyCommand" })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_lazy()"]["detects ft trigger"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ ft = "lua" })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_lazy()"]["detects keys trigger"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ keys = "<leader>x" })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_lazy()"]["returns false for no triggers"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ src = "test" })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["is_lazy()"]["handles function fields"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({
			event = function() return "BufRead" end
		})
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_lazy()"]["handles empty keys array"] = function()
    child.lua([[
		_G.result = lazy.is_lazy({ keys = {} })
	]])

    MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

-- ============================================================================
-- Filetype trigger tests
-- ============================================================================

T["ft trigger"] = MiniTest.new_set()

T["ft trigger"]["creates FileType autocmd"] = function()
    child.lua([[
		local ft_handler = require("leanpack.lazy_trigger.ft")

		-- Setup a mock pack_spec
		local pack_spec = { src = "test", name = "test" }

		-- Setup filetype trigger
		ft_handler.setup(pack_spec, "lua")

		-- Check autocmd was created
		local autocmds = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "FileType"
		})
		_G.autocmd_count = #autocmds
		_G.has_lua_pattern = false
		for _, ac in ipairs(autocmds) do
			if ac.pattern and ac.pattern:match("lua") then
				_G.has_lua_pattern = true
				break
			end
		end
	]])

    MiniTest.expect.equality(child.lua_get("_G.autocmd_count") >= 1, true)
    MiniTest.expect.equality(child.lua_get("_G.has_lua_pattern"), true)
end

T["ft trigger"]["creates autocmd for multiple filetypes"] = function()
    child.lua([[
		local ft_handler = require("leanpack.lazy_trigger.ft")

		ft_handler.setup({ src = "test", name = "test" }, { "lua", "python", "javascript" })

		local autocmds = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "FileType"
		})
		_G.autocmd_count = #autocmds
		-- Check that at least one of the filetypes is in patterns
		_G.has_some_pattern = false
		for _, ac in ipairs(autocmds) do
			if ac.pattern and (ac.pattern:match("lua") or ac.pattern:match("python") or ac.pattern:match("javascript")) then
				_G.has_some_pattern = true
				break
			end
		end
	]])

    MiniTest.expect.equality(child.lua_get("_G.autocmd_count") >= 1, true)
    MiniTest.expect.equality(child.lua_get("_G.has_some_pattern"), true)
end

-- ============================================================================
-- Event trigger tests
-- ============================================================================

T["event trigger"] = MiniTest.new_set()

T["event trigger"]["creates event autocmd"] = function()
    child.lua([[
		local event_handler = require("leanpack.lazy_trigger.event")

		event_handler.setup(
			{ src = "test", name = "test" },
			{ src = "test", name = "test" }, -- spec
			"BufRead" -- event
		)

		local autocmds = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "BufRead"
		})
		_G.autocmd_count = #autocmds
	]])

    MiniTest.expect.equality(child.lua_get("_G.autocmd_count") >= 1, true)
end

T["event trigger"]["creates autocmd for multiple events"] = function()
    child.lua([[
		local event_handler = require("leanpack.lazy_trigger.event")

		event_handler.setup(
			{ src = "test", name = "test" },
			{ src = "test", name = "test" },
			{ "BufRead", "BufWrite" }
		)

		local bufread = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "BufRead"
		})
		local bufwrite = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "BufWrite"
		})
		_G.bufread_count = #bufread
		_G.bufwrite_count = #bufwrite
	]])

    MiniTest.expect.equality(child.lua_get("_G.bufread_count") >= 1, true)
    MiniTest.expect.equality(child.lua_get("_G.bufwrite_count") >= 1, true)
end

-- ============================================================================
-- Command trigger tests
-- ============================================================================

T["cmd trigger"] = MiniTest.new_set()

T["cmd trigger"]["creates command for lazy plugin"] = function()
    child.lua([[
		local cmd_handler = require("leanpack.lazy_trigger.cmd")

		-- Setup state
		state.set_entry("test-src", {
			specs = {},
			merged_spec = { cmd = "TestCommand" }
		})

		-- Setup command trigger
		cmd_handler.setup({
			{ src = "test-src", name = "test", data = { leanpack = true } }
		})

		-- Check if command exists
		_G.cmd_exists = vim.fn.exists(":TestCommand") == 2
	]])

    MiniTest.expect.equality(child.lua_get("_G.cmd_exists"), true)
end

T["cmd trigger"]["creates commands for multiple plugins"] = function()
    child.lua([[
		local cmd_handler = require("leanpack.lazy_trigger.cmd")

		state.set_entry("src1", {
			specs = {},
			merged_spec = { cmd = "Cmd1" }
		})
		state.set_entry("src2", {
			specs = {},
			merged_spec = { cmd = { "Cmd2", "Cmd3" } }
		})

		cmd_handler.setup({
			{ src = "src1", name = "plugin1", data = { leanpack = true } },
			{ src = "src2", name = "plugin2", data = { leanpack = true } }
		})

		_G.cmd1_exists = vim.fn.exists(":Cmd1") == 2
		_G.cmd2_exists = vim.fn.exists(":Cmd2") == 2
		_G.cmd3_exists = vim.fn.exists(":Cmd3") == 2
	]])

    MiniTest.expect.equality(child.lua_get("_G.cmd1_exists"), true)
    MiniTest.expect.equality(child.lua_get("_G.cmd2_exists"), true)
    MiniTest.expect.equality(child.lua_get("_G.cmd3_exists"), true)
end

-- ============================================================================
-- Keys trigger tests
-- ============================================================================

T["keys trigger"] = MiniTest.new_set()

T["keys trigger"]["creates keymap for lazy plugin"] = function()
    child.lua([[
		local keys_handler = require("leanpack.lazy_trigger.keys")

		state.set_entry("test-src", {
			specs = {},
			merged_spec = { keys = { "<leader>x" } }
		})

		-- Setup should run without error
		local ok, err = pcall(keys_handler.setup, {
			{ src = "test-src", name = "test", data = { leanpack = true } }
		})
		_G.setup_ok = ok
	]])

    MiniTest.expect.equality(child.lua_get("_G.setup_ok"), true)
end

T["keys trigger"]["handles complex key specs"] = function()
    child.lua([[
		local keys_handler = require("leanpack.lazy_trigger.keys")

		state.set_entry("test-src", {
			specs = {},
			merged_spec = {
				keys = {
					{ "<leader>a", desc = "Action A" },
					{ "<leader>b", desc = "Action B", mode = "v" }
				}
			}
		})

		-- Setup should run without error
		local ok, err = pcall(keys_handler.setup, {
			{ src = "test-src", name = "test", data = { leanpack = true } }
		})
		_G.setup_ok = ok
	]])

    MiniTest.expect.equality(child.lua_get("_G.setup_ok"), true)
end

-- ============================================================================
-- process_lazy integration tests
-- ============================================================================

T["process_lazy()"] = MiniTest.new_set()

T["process_lazy()"]["skips when pending builds exist"] = function()
    child.lua([[
		-- Mark a pending build
		state.mark_pending_build("test-src")

		-- Track if lazy triggers were processed
		_G.processed = false
		local orig_event_setup = require("leanpack.lazy_trigger.event").setup
		require("leanpack.lazy_trigger.event").setup = function()
			_G.processed = true
		end

		-- Try to process lazy plugins
		lazy.process_lazy({ lazy_packs = {} })

		require("leanpack.lazy_trigger.event").setup = orig_event_setup
	]])

    MiniTest.expect.equality(child.lua_get("_G.processed"), false)
end

T["process_lazy()"]["processes lazy plugins with triggers"] = function()
    child.lua([[
		-- Setup a lazy plugin with event trigger
		state.set_entry("test-src", {
			specs = {},
			merged_spec = { event = "BufRead" }
		})

		-- Process lazy plugins
		lazy.process_lazy({
			lazy_packs = {
				{ src = "test-src", name = "test", data = { leanpack = true } }
			}
		})

		-- Check autocmd was created
		local autocmds = vim.api.nvim_get_autocmds({
			group = state.lazy_group,
			event = "BufRead"
		})
		_G.autocmd_count = #autocmds
	]])

    MiniTest.expect.equality(child.lua_get("_G.autocmd_count") >= 1, true)
end

return T
