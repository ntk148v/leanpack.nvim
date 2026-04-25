---@module 'tests.spec_spec'
-- Tests for leanpack.spec module

local helpers = require("tests.helpers")
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
				_G.spec = require("leanpack.spec")
			]])
		end,
		post_once = child.stop,
	},
})

-- ============================================================================
-- normalize_spec tests
-- ============================================================================

T["normalize_spec()"] = MiniTest.new_set()

T["normalize_spec()"]["converts short name to full spec"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({ "owner/repo" })
	]])

	local result = child.lua_get("_G.result")
	local src = child.lua_get("_G.src")

	MiniTest.expect.equality(src, "https://github.com/owner/repo")
	MiniTest.expect.equality(result.name, "repo")
	MiniTest.expect.equality(result.src, "https://github.com/owner/repo")
	MiniTest.expect.equality(result.priority, 50)
end

T["normalize_spec()"]["preserves explicit src"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			src = "https://gitlab.com/user/plugin"
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.src, "https://gitlab.com/user/plugin")
	MiniTest.expect.equality(result.name, "plugin")
end

T["normalize_spec()"]["handles url field"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			url = "https://github.com/user/plugin"
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.src, "https://github.com/user/plugin")
end

T["normalize_spec()"]["handles dir field with expansion"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			dir = "~/projects/my-plugin"
		})
	]])

	local result = child.lua_get("_G.result")
	local expected = vim.fn.expand("~/projects/my-plugin")
	MiniTest.expect.equality(result.src, expected)
end

T["normalize_spec()"]["handles dev mode"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			[1] = "user/my-plugin",
			dev = true
		})
	]])

	local result = child.lua_get("_G.result")
	local expected = vim.fn.expand("~/projects/my-plugin")
	MiniTest.expect.equality(result.src, expected)
end

T["normalize_spec()"]["resolves version field with semver wildcard"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "1.*" })
	]])

	local result = child.lua_get("_G.result")
	-- Should be a table (vim.VersionRange)
	MiniTest.expect.equality(type(result.version), "table")
end

T["normalize_spec()"]["resolves version field falling back to literal"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "main" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.version, "main")
end

T["normalize_spec()"]["handles version = false"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = false })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.version, nil)
end

T["normalize_spec()"]["resolves sem_version to range"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", sem_version = ">=1.0.0" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(type(result.version), "table")
end

T["normalize_spec()"]["resolves branch as version"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", branch = "main" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.version, "main")
end

T["normalize_spec()"]["resolves tag as version"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", tag = "stable" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.version, "stable")
end

T["normalize_spec()"]["resolves commit as version"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", commit = "abc123" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.version, "abc123")
end

T["normalize_spec()"]["handles enabled function"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			enabled = function() return false end
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result, vim.NIL)
end

T["normalize_spec()"]["handles enabled boolean"] = function()
	child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			"user/repo",
			enabled = true
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result ~= vim.NIL, true)

	child.lua([[
		_G.result2 = spec.normalize_spec({
			"user/repo",
			enabled = false
		})
	]])

	local result2 = child.lua_get("_G.result2")
	MiniTest.expect.equality(result2, vim.NIL)
end

T["normalize_spec()"]["preserves lazy triggers"] = function()
	child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			event = "BufRead",
			cmd = "MyCommand",
			ft = "lua",
			keys = { "<leader>x" }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.event, { "BufRead" })
	MiniTest.expect.equality(result.cmd, { "MyCommand" })
	MiniTest.expect.equality(result.ft, { "lua" })
	MiniTest.expect.equality(result.keys[1], "<leader>x")
end

T["normalize_spec()"]["preserves hooks"] = function()
	child.lua([[
		local fn = function() end
		_G.result = spec.normalize_spec({
			"user/repo",
			init = fn,
			config = fn,
			build = "make",
			opts = { key = "value" }
		})
		_G.has_init = _G.result.init ~= nil
		_G.has_config = _G.result.config ~= nil
		_G.build_value = _G.result.build
		_G.opts_key = _G.result.opts.key
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_init"), true)
	MiniTest.expect.equality(child.lua_get("_G.has_config"), true)
	MiniTest.expect.equality(child.lua_get("_G.build_value"), "make")
	MiniTest.expect.equality(child.lua_get("_G.opts_key"), "value")
end

T["normalize_spec()"]["applies defaults"] = function()
	child.lua([[
		local defaults = { cond = function() return true end }
		_G.result = spec.normalize_spec({ "user/repo" }, defaults)
		_G.has_cond = _G.result.cond ~= nil
	]])

	MiniTest.expect.equality(child.lua_get("_G.has_cond"), true)
end

-- ============================================================================
-- merge_specs tests
-- ============================================================================

T["merge_specs()"] = MiniTest.new_set()

T["merge_specs()"]["returns empty table for empty input"] = function()
	child.lua([[
		_G.result = spec.merge_specs({})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(type(result), "table")
	MiniTest.expect.equality(next(result), nil) -- empty table
end

T["merge_specs()"]["returns single spec unchanged"] = function()
	child.lua([[
		_G.result = spec.merge_specs({{ src = "test", name = "test" }})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.src, "test")
	MiniTest.expect.equality(result.name, "test")
end

T["merge_specs()"]["merges opts tables deeply"] = function()
	child.lua([[
		_G.result = spec.merge_specs({
			{ src = "test", opts = { a = 1, nested = { x = 1 } } },
			{ src = "test", opts = { b = 2, nested = { y = 2 } } }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.opts.a, 1)
	MiniTest.expect.equality(result.opts.b, 2)
	MiniTest.expect.equality(result.opts.nested.x, 1)
	MiniTest.expect.equality(result.opts.nested.y, 2)
end

T["merge_specs()"]["function opts takes precedence over table"] = function()
	child.lua([[
		local fn = function() return {} end
		_G.result = spec.merge_specs({
			{ src = "test", opts = { a = 1 } },
			{ src = "test", opts = fn }
		})
		_G.opts_is_function = type(_G.result.opts) == "function"
	]])

	MiniTest.expect.equality(child.lua_get("_G.opts_is_function"), true)
end

T["merge_specs()"]["merges dependencies uniquely"] = function()
	child.lua([[
		_G.result = spec.merge_specs({
			{ src = "test", dependencies = { "dep1", "dep2" } },
			{ src = "test", dependencies = { "dep2", "dep3" } }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result.dependencies, 3)
	MiniTest.expect.equality(result.dependencies[1], "dep1")
	MiniTest.expect.equality(result.dependencies[2], "dep2")
	MiniTest.expect.equality(result.dependencies[3], "dep3")
end

T["merge_specs()"]["merges trigger arrays"] = function()
	child.lua([[
		_G.result = spec.merge_specs({
			{ src = "test", event = "BufRead", cmd = "Cmd1" },
			{ src = "test", event = "BufWrite", cmd = "Cmd2" }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result.event, 2)
	MiniTest.expect.equality(result.event[1], "BufRead")
	MiniTest.expect.equality(result.event[2], "BufWrite")
	MiniTest.expect.equality(#result.cmd, 2)
end

T["merge_specs()"]["takes first non-nil scalar value"] = function()
	child.lua([[
		_G.result = spec.merge_specs({
			{ src = "test", priority = 100, lazy = nil },
			{ src = "test", priority = nil, lazy = true }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.priority, 100)
	MiniTest.expect.equality(result.lazy, true)
end

-- ============================================================================
-- to_pack_spec tests
-- ============================================================================

T["to_pack_spec()"] = MiniTest.new_set()

T["to_pack_spec()"]["converts to vim.pack.Spec format"] = function()
	child.lua([[
		_G.result = spec.to_pack_spec({
			src = "https://github.com/user/repo",
			name = "repo",
			version = "v1.0.0",
			priority = 100
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result.src, "https://github.com/user/repo")
	MiniTest.expect.equality(result.name, "repo")
	MiniTest.expect.equality(result.version, "v1.0.0")
	MiniTest.expect.equality(result.data.leanpack, true)
	MiniTest.expect.equality(result.data.priority, 100)
end

-- ============================================================================
-- normalize_list tests
-- ============================================================================

T["normalize_list()"] = MiniTest.new_set()

T["normalize_list()"]["returns nil for nil input"] = function()
	child.lua([[
		_G.result = spec.normalize_list(nil)
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result, vim.NIL)
end

T["normalize_list()"]["wraps string in table"] = function()
	child.lua([[
		_G.result = spec.normalize_list("value")
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(type(result), "table")
	MiniTest.expect.equality(#result, 1)
	MiniTest.expect.equality(result[1], "value")
end

T["normalize_list()"]["returns table unchanged"] = function()
	child.lua([[
		_G.result = spec.normalize_list({ "a", "b", "c" })
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 3)
	MiniTest.expect.equality(result[1], "a")
end

-- ============================================================================
-- sort_by_priority tests
-- ============================================================================

T["sort_by_priority()"] = MiniTest.new_set()

T["sort_by_priority()"]["sorts by priority descending"] = function()
	child.lua([[
		_G.result = spec.sort_by_priority({
			{ src = "a", priority = 50 },
			{ src = "b", priority = 100 },
			{ src = "c", priority = 75 }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result[1].src, "b") -- 100
	MiniTest.expect.equality(result[2].src, "c") -- 75
	MiniTest.expect.equality(result[3].src, "a") -- 50
end

T["sort_by_priority()"]["uses default priority of 50"] = function()
	child.lua([[
		_G.result = spec.sort_by_priority({
			{ src = "a" },
			{ src = "b", priority = 100 }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result[1].src, "b") -- 100
	MiniTest.expect.equality(result[2].src, "a") -- default 50
end

return T
