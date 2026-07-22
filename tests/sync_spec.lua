---@module 'tests.sync_spec'
-- Tests for automatic sync (orphan removal) during setup

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
				vim.pack.del = function() end

				_G.leanpack = require("leanpack")
			]])
		end,
		post_once = child.stop,
	},
})

T["sync"] = MiniTest.new_set()

T["sync"]["does not remove plugins when sync is false (default)"] = function()
	child.lua([[
		local del_calls = {}
		vim.pack.del = function(names)
			table.insert(del_calls, names)
		end

		-- Mock fs_scandir to simulate an orphaned plugin on disk
		local original_scandir = vim.uv.fs_scandir
		local original_scandir_next = vim.uv.fs_scandir_next
		local scan_items = {
			{ "configured-plugin", "directory" },
			{ "orphaned-plugin", "directory" },
		}
		local scan_idx = 0

		vim.uv.fs_scandir = function(path)
			if path:match("opt/$") then
				scan_idx = 0
				return "mock_handle"
			end
			return original_scandir(path)
		end

		vim.uv.fs_scandir_next = function(handle)
			if handle == "mock_handle" then
				scan_idx = scan_idx + 1
				if scan_idx <= #scan_items then
					return scan_items[scan_idx][1], scan_items[scan_idx][2]
				end
				return nil
			end
			return original_scandir_next(handle)
		end

		-- Mock fs_stat so configured-plugin appears installed
		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path)
			if path:match("configured%-plugin$") then
				return { type = "directory" }
			end
			return nil
		end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			-- sync is false by default
			plugins = {
				{ "owner/configured-plugin", lazy = false },
			},
		})

		_G.del_calls = del_calls

		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_scandir_next
		vim.uv.fs_stat = original_stat
	]])

	-- No plugins should be deleted when sync is off
	MiniTest.expect.equality(child.lua_get("_G.del_calls"), {})
end

T["sync"]["removes orphaned plugins when sync is true"] = function()
	child.lua([[
		local del_calls = {}
		vim.pack.del = function(names)
			table.insert(del_calls, names)
		end

		-- Mock fs_scandir to simulate plugins on disk
		local original_scandir = vim.uv.fs_scandir
		local original_scandir_next = vim.uv.fs_scandir_next
		local scan_items = {
			{ "configured-plugin", "directory" },
			{ "orphaned-plugin", "directory" },
			{ "another-orphan", "directory" },
		}
		local scan_idx = 0

		vim.uv.fs_scandir = function(path)
			if path:match("opt/$") then
				scan_idx = 0
				return "mock_handle"
			end
			return original_scandir(path)
		end

		vim.uv.fs_scandir_next = function(handle)
			if handle == "mock_handle" then
				scan_idx = scan_idx + 1
				if scan_idx <= #scan_items then
					return scan_items[scan_idx][1], scan_items[scan_idx][2]
				end
				return nil
			end
			return original_scandir_next(handle)
		end

		-- Mock fs_stat so configured-plugin appears installed
		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path)
			if path:match("configured%-plugin$") then
				return { type = "directory" }
			end
			return nil
		end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			sync = true,
			plugins = {
				{ "owner/configured-plugin", lazy = false },
			},
		})

		_G.del_calls = del_calls

		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_scandir_next
		vim.uv.fs_stat = original_stat
	]])

	local del_calls = child.lua_get("_G.del_calls")
	MiniTest.expect.equality(#del_calls, 1)

	-- Both orphaned plugins should be deleted in a single call
	local deleted = del_calls[1]
	table.sort(deleted)
	MiniTest.expect.equality(deleted, { "another-orphan", "orphaned-plugin" })
end

T["sync"]["never removes leanpack.nvim itself"] = function()
	child.lua([[
		local del_calls = {}
		vim.pack.del = function(names)
			table.insert(del_calls, names)
		end

		-- Mock fs_scandir: leanpack.nvim is on disk but not in config
		local original_scandir = vim.uv.fs_scandir
		local original_scandir_next = vim.uv.fs_scandir_next
		local scan_items = {
			{ "leanpack.nvim", "directory" },
			{ "orphaned-plugin", "directory" },
		}
		local scan_idx = 0

		vim.uv.fs_scandir = function(path)
			if path:match("opt/$") then
				scan_idx = 0
				return "mock_handle"
			end
			return original_scandir(path)
		end

		vim.uv.fs_scandir_next = function(handle)
			if handle == "mock_handle" then
				scan_idx = scan_idx + 1
				if scan_idx <= #scan_items then
					return scan_items[scan_idx][1], scan_items[scan_idx][2]
				end
				return nil
			end
			return original_scandir_next(handle)
		end

		-- No plugins are installed
		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path) return nil end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			sync = true,
			plugins = {},
		})

		_G.del_calls = del_calls

		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_scandir_next
		vim.uv.fs_stat = original_stat
	]])

	local del_calls = child.lua_get("_G.del_calls")
	MiniTest.expect.equality(#del_calls, 1)
	-- Only orphaned-plugin should be deleted, leanpack.nvim is protected
	MiniTest.expect.equality(del_calls[1], { "orphaned-plugin" })
end

T["sync"]["does not call del when no orphans exist"] = function()
	child.lua([[
		local del_calls = {}
		vim.pack.del = function(names)
			table.insert(del_calls, names)
		end

		-- Mock fs_scandir: only the configured plugin is on disk
		local original_scandir = vim.uv.fs_scandir
		local original_scandir_next = vim.uv.fs_scandir_next
		local scan_items = {
			{ "configured-plugin", "directory" },
		}
		local scan_idx = 0

		vim.uv.fs_scandir = function(path)
			if path:match("opt/$") then
				scan_idx = 0
				return "mock_handle"
			end
			return original_scandir(path)
		end

		vim.uv.fs_scandir_next = function(handle)
			if handle == "mock_handle" then
				scan_idx = scan_idx + 1
				if scan_idx <= #scan_items then
					return scan_items[scan_idx][1], scan_items[scan_idx][2]
				end
				return nil
			end
			return original_scandir_next(handle)
		end

		-- configured-plugin is installed
		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path)
			if path:match("configured%-plugin$") then
				return { type = "directory" }
			end
			return nil
		end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			sync = true,
			plugins = {
				{ "owner/configured-plugin", lazy = false },
			},
		})

		_G.del_calls = del_calls

		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_scandir_next
		vim.uv.fs_stat = original_stat
	]])

	-- No deletions when everything is in sync
	MiniTest.expect.equality(child.lua_get("_G.del_calls"), {})
end

T["sync"]["ignores non-directory entries in opt path"] = function()
	child.lua([[
		local del_calls = {}
		vim.pack.del = function(names)
			table.insert(del_calls, names)
		end

		-- Mock fs_scandir: files should be ignored, only directories matter
		local original_scandir = vim.uv.fs_scandir
		local original_scandir_next = vim.uv.fs_scandir_next
		local scan_items = {
			{ "some-file.txt", "file" },
			{ ".DS_Store", "file" },
		}
		local scan_idx = 0

		vim.uv.fs_scandir = function(path)
			if path:match("opt/$") then
				scan_idx = 0
				return "mock_handle"
			end
			return original_scandir(path)
		end

		vim.uv.fs_scandir_next = function(handle)
			if handle == "mock_handle" then
				scan_idx = scan_idx + 1
				if scan_idx <= #scan_items then
					return scan_items[scan_idx][1], scan_items[scan_idx][2]
				end
				return nil
			end
			return original_scandir_next(handle)
		end

		local original_stat = vim.uv.fs_stat
		vim.uv.fs_stat = function(path) return nil end

		leanpack.setup({
			performance = { rtp_prune = false, vim_loader = false },
			sync = true,
			plugins = {},
		})

		_G.del_calls = del_calls

		vim.uv.fs_scandir = original_scandir
		vim.uv.fs_scandir_next = original_scandir_next
		vim.uv.fs_stat = original_stat
	]])

	-- No deletions for non-directory entries
	MiniTest.expect.equality(child.lua_get("_G.del_calls"), {})
end

return T
