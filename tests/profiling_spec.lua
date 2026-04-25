---@module 'tests.profiling_spec'
-- Tests for leanpack.nvim profiling

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
				
				-- Mock vim.pack to prevent network calls
				vim.pack = vim.pack or {}
				vim.pack.add = function() end
				vim.pack.get = function() return {} end
				
				_G.leanpack = require("leanpack")
			]])
		end,
		post_once = child.stop,
	},
})

T["Profiling"] = MiniTest.new_set()

T["Profiling"]["can be enabled via setup({ profiling = true })"] = function()
	child.lua([[
		leanpack.setup({
			profiling = true,
			plugins = {
				{ src = "test/plugin", lazy = false }
			}
		})
		_G.profile = leanpack.get_profile_data()
	]])

	local profile = child.lua_get("_G.profile")
	MiniTest.expect.equality(profile._total > 0, true)
	MiniTest.expect.equality(profile.import_specs ~= nil, true)
	MiniTest.expect.equality(profile.process_all ~= nil, true)
end

T["Profiling"]["can be enabled via setup({ profiling = { enabled = true } })"] = function()
	child.lua([[
		leanpack.setup({
			profiling = { enabled = true },
			plugins = {
				{ src = "test/plugin", lazy = false }
			}
		})
		_G.profile = leanpack.get_profile_data()
	]])

	local profile = child.lua_get("_G.profile")
	MiniTest.expect.equality(profile._total > 0, true)
	MiniTest.expect.equality(profile.import_specs ~= nil, true)
end

T["Profiling"]["is disabled by default"] = function()
	child.lua([[
		leanpack.setup({
			plugins = {
				{ src = "test/plugin", lazy = false }
			}
		})
		_G.profile = leanpack.get_profile_data()
	]])

	local profile = child.lua_get("_G.profile")
	MiniTest.expect.equality(profile._total, 0)
end

return T
