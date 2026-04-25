---@module 'tests.installation_spec'
-- Tests for background installation registration and UI status

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
				
				-- Mock vim.pack globally for tests
				vim.pack = vim.pack or {}
				vim.pack.add = function() end
				vim.pack.get = function() return {} end
				
				_G.leanpack = require("leanpack")
			]])
		end,
		post_once = child.stop,
	},
})

T["Background Installation"] = MiniTest.new_set()

T["Background Installation"]["registers lazy plugins with vim.pack.add(..., { load = false })"] = function()
	child.lua([[
		local add_calls = {}
		vim.pack.add = function(specs, opts)
			table.insert(add_calls, { specs = specs, opts = opts })
		end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			plugins = {
				{ src = "startup/plugin", lazy = false },
				{ src = "lazy/plugin", event = "BufRead" },
			}
		})
		_G.add_calls = add_calls
	]])

	local add_calls = child.lua_get("_G.add_calls")
	MiniTest.expect.equality(#add_calls, 2)
	local lazy_call = add_calls[2]
	MiniTest.expect.equality(lazy_call.opts.load, false)
end

T["UI Status"] = MiniTest.new_set()

T["UI Status"]["shows '✗' for missing plugins"] = function()
	child.lua([[
		-- Mock fs_stat to return nil (missing)
		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path) return nil end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			plugins = {
				{ src = "missing/plugin", lazy = true },
			}
		})
		
		local ui = require("leanpack.ui")
		ui.open()
		_G.buffer_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		_G.plugin_entry = require("leanpack.state").get_entry("missing/plugin")
	]])

	local content = child.lua_get("_G.buffer_content")
	-- print(vim.inspect(content)) -- debug
	local found_missing = false
	for _, line in ipairs(content) do
		if line:find("✗") then
			found_missing = true
		end
	end
	
	if not found_missing then
		local entry = child.lua_get("_G.plugin_entry")
		error("Entry info: " .. vim.inspect(entry) .. "\nBuffer: " .. vim.inspect(content))
	end
	
	MiniTest.expect.equality(found_missing, true)
end

T["UI Timer"] = MiniTest.new_set()

T["UI Timer"]["starts timer when opened and stops when closed"] = function()
	child.lua([[
		local ui = require("leanpack.ui")
		
		local timer_created = false
		local timer_started = false
		local timer_stopped = false
		local timer_closed = false
		
		local mock_timer = {
			start = function() timer_started = true end,
			stop = function() timer_stopped = true end,
			close = function() timer_closed = true end,
			is_closing = function() return timer_closed end,
		}
		
		local original_new_timer = vim.uv.new_timer
		vim.uv.new_timer = function()
			timer_created = true
			return mock_timer
		end
		
		ui.open()
		_G.timer_created = timer_created
		_G.timer_started = timer_started
		
		ui.close()
		_G.timer_stopped = timer_stopped
		_G.timer_closed = timer_closed
		
		vim.uv.new_timer = original_new_timer
	]])
	
	MiniTest.expect.equality(child.lua_get("_G.timer_created"), true)
	MiniTest.expect.equality(child.lua_get("_G.timer_started"), true)
	MiniTest.expect.equality(child.lua_get("_G.timer_stopped"), true)
	MiniTest.expect.equality(child.lua_get("_G.timer_closed"), true)
end

return T
