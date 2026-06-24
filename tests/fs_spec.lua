---@module 'tests.fs_spec'
-- Tests for leanpack.fs module

local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
				vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
				_G.fs = require("leanpack.fs")
			]])
        end,
        post_once = child.stop,
    },
})

T["source_ftdetect_dir()"] = MiniTest.new_set()

T["source_ftdetect_dir()"]["escapes paths with spaces and command separators"] = function()
    child.lua([[
		local commands = {}
		local original_cmd = vim.cmd
		vim.cmd = function(cmd)
			table.insert(commands, cmd)
		end

		local original_scandir = vim.uv.fs_scandir
		local original_next = vim.uv.fs_scandir_next

		vim.uv.fs_scandir = function(path)
			_G.scanned_path = path
			return true
		end

		local entries = {
			{ "a file.lua", "file" },
			{ "evil|echo.lua", "file" },
			{ "skip.txt", "file" },
			{ "b.vim", "file" },
		}
		local index = 0
		vim.uv.fs_scandir_next = function()
			index = index + 1
			local entry = entries[index]
			if not entry then
				return nil
			end
			return entry[1], entry[2]
		end

		fs.source_ftdetect_dir("/tmp/plugin path/ftdetect")

		_G.commands = commands
		vim.cmd = original_cmd
		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_next
	]])

    local commands = child.lua_get("_G.commands")
    MiniTest.expect.equality(#commands, 3)
    -- Each command should start with silent! source
    for _, cmd in ipairs(commands) do
        MiniTest.expect.equality(cmd:match("^silent! source ") ~= nil, true)
    end
    -- At least one command contains fnameescaped space
    local has_escaped_space = false
    for _, cmd in ipairs(commands) do
        if cmd:match("source .+\\ .+") then
            has_escaped_space = true
            break
        end
    end
    MiniTest.expect.equality(has_escaped_space, true)
end

return T
