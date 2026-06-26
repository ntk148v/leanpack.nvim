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

T["concurrency guard"] = MiniTest.new_set()

T["concurrency guard"]["rejects duplicate install before first completes"] = function()
    child.lua([[
		local original_jobstart = vim.fn.jobstart
		local original_notify = vim.notify
		_G.running = {}
		_G.warns = {}

		vim.fn.jobstart = function(cmd, opts)
			_G.running[#_G.running + 1] = cmd
			return 1
		end

		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN then
				_G.warns[#_G.warns + 1] = msg
			end
		end

		job.run("install", { { src = "p1" } }, function() end)
		job.run("install", { { src = "p2" } }, function() end)

		_G.running_count = #_G.running
		_G.warn_count = #_G.warns

		vim.fn.jobstart = original_jobstart
		vim.notify = original_notify
	]])

    MiniTest.expect.equality(child.lua_get("_G.running_count"), 1)
    MiniTest.expect.equality(child.lua_get("_G.warn_count") >= 1, true)
end

T["concurrency guard"]["clears lane when install payload write fails"] = function()
    child.lua([[
		local original_writefile = vim.fn.writefile
		local original_jobstart = vim.fn.jobstart
		local calls = 0

		vim.fn.writefile = function()
			error("write failed")
		end
		vim.fn.jobstart = function()
			calls = calls + 1
			return 1
		end

		job.run("install", { { src = "p1" } }, function() end)

		vim.fn.writefile = original_writefile
		job.run("install", { { src = "p2" } }, function() end)

		_G.calls = calls
		vim.fn.jobstart = original_jobstart
	]])

    MiniTest.expect.equality(child.lua_get("_G.calls"), 1)
end

return T
