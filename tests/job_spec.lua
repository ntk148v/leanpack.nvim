---@module 'tests.job_spec'
-- Tests for leanpack.job

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
				_G.job = require("leanpack.job")
			]])
        end,
        post_once = child.stop,
    },
})

T["update"] = MiniTest.new_set()

T["update"]["emits parseable Lua for targeted updates"] = function()
    child.lua([[
		local original_jobstart = vim.fn.jobstart

		vim.fn.jobstart = function(cmd)
			_G.job_cmd = cmd
			return 1
		end

		job.run("update", { "target-plugin" }, function() end)

		vim.fn.jobstart = original_jobstart

		for i, arg in ipairs(_G.job_cmd) do
			if arg == "-c" and _G.job_cmd[i + 1] and _G.job_cmd[i + 1]:match("^lua ") then
				_G.lua_chunk = _G.job_cmd[i + 1]:sub(5)
				break
			end
		end

		_G.load_ok = load(_G.lua_chunk) ~= nil
	]])

    MiniTest.expect.equality(child.lua_get("_G.load_ok"), true)
end

return T
