---@module 'tests.deps_spec'
-- Tests for parcel.deps module

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
				_G.deps = require("parcel.deps")
				_G.spec_mod = require("parcel.spec")
				_G.state = require("parcel.state")
			]])
		end,
		post_once = child.stop,
	},
})

-- ============================================================================
-- resolve_dependencies tests
-- ============================================================================

T["resolve_dependencies()"] = MiniTest.new_set()

T["resolve_dependencies()"]["returns empty for no dependencies"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({ src = "test" }, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(type(result), "table")
	MiniTest.expect.equality(#result, 0)
end

T["resolve_dependencies()"]["resolves string dependency"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = { "owner/dep-plugin" }
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 1)
	MiniTest.expect.equality(result[1].src, "https://github.com/owner/dep-plugin")
	MiniTest.expect.equality(result[1]._is_dependency, true)
end

T["resolve_dependencies()"]["resolves table dependency"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = { { "owner/dep-plugin", priority = 100 } }
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 1)
	MiniTest.expect.equality(result[1].src, "https://github.com/owner/dep-plugin")
	MiniTest.expect.equality(result[1].priority, 100)
end

T["resolve_dependencies()"]["resolves multiple dependencies"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = { "owner/dep1", "owner/dep2" }
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 2)
end

T["resolve_dependencies()"]["resolves multi-string table (lazy.nvim format)"] = function()
	child.lua([[
		-- lazy.nvim allows { "a", "b", "c" } as a single entry in dependencies
		-- meaning three separate dependencies
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = {
				{ "owner/dep1", "owner/dep2", "owner/dep3" }
			}
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 3)
	MiniTest.expect.equality(result[1].src, "https://github.com/owner/dep1")
	MiniTest.expect.equality(result[2].src, "https://github.com/owner/dep2")
	MiniTest.expect.equality(result[3].src, "https://github.com/owner/dep3")
end

T["resolve_dependencies()"]["multi-string table tracks all dependency relationships"] = function()
	child.lua([[
		deps.resolve_dependencies({
			src = "https://github.com/parent/plugin",
			dependencies = {
				{ "owner/dep1", "owner/dep2" }
			}
		}, {})
		_G.deps_result = state.get_dependencies("https://github.com/parent/plugin")
	]])

	local deps_result = child.lua_get("_G.deps_result")
	MiniTest.expect.equality(deps_result["https://github.com/owner/dep1"] ~= nil, true)
	MiniTest.expect.equality(deps_result["https://github.com/owner/dep2"] ~= nil, true)
end

T["resolve_dependencies()"]["preserves optional flag from parent"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({
			src = "parent",
			optional = true,
			dependencies = { "owner/dep-plugin" }
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result[1].optional, true)
end

T["resolve_dependencies()"]["does not override explicit optional on dep"] = function()
	child.lua([[
		_G.result = deps.resolve_dependencies({
			src = "parent",
			optional = true,
			dependencies = { { "owner/dep-plugin", optional = false } }
		}, {})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result[1].optional, false)
end

T["resolve_dependencies()"]["tracks dependency relationships in state"] = function()
	child.lua([[
		deps.resolve_dependencies({
			src = "https://github.com/parent/parent",
			dependencies = { "owner/child" }
		}, {})
		_G.deps = state.get_dependencies("https://github.com/parent/parent")
		_G.reverse = state.get_reverse_dependencies("https://github.com/owner/child")
	]])

	local deps_result = child.lua_get("_G.deps")
	local reverse = child.lua_get("_G.reverse")
	MiniTest.expect.equality(deps_result ~= vim.NIL, true)
	MiniTest.expect.equality(reverse ~= vim.NIL, true)
end

-- ============================================================================
-- toposort_startup tests
-- ============================================================================

T["toposort_startup()"] = MiniTest.new_set()

T["toposort_startup()"]["returns empty for empty input"] = function()
	child.lua([[
		_G.result = deps.toposort_startup({})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 0)
end

T["toposort_startup()"]["returns single pack unchanged"] = function()
	child.lua([[
		_G.result = deps.toposort_startup({
			{ src = "test", name = "test", data = { priority = 50 } }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(#result, 1)
	MiniTest.expect.equality(result[1].src, "test")
end

T["toposort_startup()"]["sorts by priority descending"] = function()
	child.lua([[
		_G.result = deps.toposort_startup({
			{ src = "low", name = "low", data = { priority = 50 } },
			{ src = "high", name = "high", data = { priority = 100 } },
			{ src = "medium", name = "medium", data = { priority = 75 } }
		})
	]])

	local result = child.lua_get("_G.result")
	MiniTest.expect.equality(result[1].src, "high")
	MiniTest.expect.equality(result[2].src, "medium")
	MiniTest.expect.equality(result[3].src, "low")
end

T["toposort_startup()"]["respects dependency order"] = function()
	child.lua([[
		-- Setup: parent depends on child
		state.add_dependency("parent", "child")
		
		_G.result = deps.toposort_startup({
			{ src = "parent", name = "parent", data = { priority = 50 } },
			{ src = "child", name = "child", data = { priority = 50 } }
		})
	]])

	local result = child.lua_get("_G.result")
	-- Child should come before parent
	local child_idx, parent_idx
	for i, p in ipairs(result) do
		if p.src == "child" then child_idx = i end
		if p.src == "parent" then parent_idx = i end
	end
	MiniTest.expect.equality(child_idx ~= nil, true)
	MiniTest.expect.equality(parent_idx ~= nil, true)
	MiniTest.expect.equality(child_idx < parent_idx, true)
end

T["toposort_startup()"]["handles deep dependencies"] = function()
	child.lua([[
		-- a -> b -> c (a depends on b, b depends on c)
		state.add_dependency("a", "b")
		state.add_dependency("b", "c")
		
		_G.result = deps.toposort_startup({
			{ src = "a", name = "a", data = { priority = 50 } },
			{ src = "b", name = "b", data = { priority = 50 } },
			{ src = "c", name = "c", data = { priority = 50 } }
		})
	]])

	local result = child.lua_get("_G.result")
	-- Order should be c, b, a
	local indices = {}
	for i, p in ipairs(result) do
		indices[p.src] = i
	end
	MiniTest.expect.equality(indices.c < indices.b, true)
	MiniTest.expect.equality(indices.b < indices.a, true)
end

T["toposort_startup()"]["handles diamond dependencies"] = function()
	child.lua([[
		--   a
		--  / \
		-- b   c
		--  \ /
		--   d
		state.add_dependency("a", "b")
		state.add_dependency("a", "c")
		state.add_dependency("b", "d")
		state.add_dependency("c", "d")
		
		_G.result = deps.toposort_startup({
			{ src = "a", name = "a", data = { priority = 50 } },
			{ src = "b", name = "b", data = { priority = 50 } },
			{ src = "c", name = "c", data = { priority = 50 } },
			{ src = "d", name = "d", data = { priority = 50 } }
		})
	]])

	local result = child.lua_get("_G.result")
	local indices = {}
	for i, p in ipairs(result) do
		indices[p.src] = i
	end
	-- d must come before b and c, b and c must come before a
	MiniTest.expect.equality(indices.d < indices.b, true)
	MiniTest.expect.equality(indices.d < indices.c, true)
	MiniTest.expect.equality(indices.b < indices.a, true)
	MiniTest.expect.equality(indices.c < indices.a, true)
end

T["toposort_startup()"]["handles circular dependency gracefully"] = function()
	child.lua([[
		-- a -> b -> a (circular)
		state.add_dependency("a", "b")
		state.add_dependency("b", "a")
		
		-- Capture warning
		_G.warnings = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(_G.warnings, msg)
		end
		
		_G.result = deps.toposort_startup({
			{ src = "a", name = "a", data = { priority = 50 } },
			{ src = "b", name = "b", data = { priority = 50 } }
		})
		
		vim.notify = orig_notify
	]])

	local warnings = child.lua_get("_G.warnings")
	local found_warning = false
	for _, w in ipairs(warnings) do
		if w:match("Circular dependency") then
			found_warning = true
			break
		end
	end
	MiniTest.expect.equality(found_warning, true)
end

-- ============================================================================
-- is_dependency_only tests
-- ============================================================================

T["is_dependency_only()"] = MiniTest.new_set()

T["is_dependency_only()"]["returns false for unknown src"] = function()
	child.lua([[
		_G.result = deps.is_dependency_only("unknown")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["is_dependency_only()"]["returns true when all specs are dependencies"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = {
				{ src = "test", _is_dependency = true },
				{ src = "test", _is_dependency = true }
			}
		})
		_G.result = deps.is_dependency_only("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), true)
end

T["is_dependency_only()"]["returns false when any spec is not a dependency"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = {
				{ src = "test", _is_dependency = true },
				{ src = "test", _is_dependency = false }
			}
		})
		_G.result = deps.is_dependency_only("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

T["is_dependency_only()"]["returns false when no specs have _is_dependency flag"] = function()
	child.lua([[
		state.set_entry("test-src", {
			specs = {
				{ src = "test" },
				{ src = "test" }
			}
		})
		_G.result = deps.is_dependency_only("test-src")
	]])

	MiniTest.expect.equality(child.lua_get("_G.result"), false)
end

-- ============================================================================
-- Integration tests
-- ============================================================================

T["integration"] = MiniTest.new_set()

T["integration"]["complex dependency scenario"] = function()
	child.lua([[
		-- Setup a complex scenario:
		-- plugin-a depends on plugin-b and plugin-c
		-- plugin-b depends on plugin-d
		-- plugin-c depends on plugin-d
		-- plugin-e has no dependencies
		
		local ctx = { defaults = {} }
		
		-- Register dependencies
		deps.resolve_dependencies({
			src = "plugin-a",
			dependencies = { "owner/plugin-b", "owner/plugin-c" }
		}, ctx)
		
		deps.resolve_dependencies({
			src = "https://github.com/owner/plugin-b",
			dependencies = { "owner/plugin-d" }
		}, ctx)
		
		deps.resolve_dependencies({
			src = "https://github.com/owner/plugin-c",
			dependencies = { "owner/plugin-d" }
		}, ctx)
		
		-- Get all dependencies
		_G.deps_a = state.get_dependencies("plugin-a")
		_G.deps_b = state.get_dependencies("https://github.com/owner/plugin-b")
		_G.deps_c = state.get_dependencies("https://github.com/owner/plugin-c")
		_G.deps_d = state.get_dependencies("https://github.com/owner/plugin-d")
		
		-- Get reverse dependencies
		_G.reverse_d = state.get_reverse_dependencies("https://github.com/owner/plugin-d")
	]])

	local deps_a = child.lua_get("_G.deps_a")
	local deps_b = child.lua_get("_G.deps_b")
	local deps_c = child.lua_get("_G.deps_c")
	local deps_d = child.lua_get("_G.deps_d")
	local reverse_d = child.lua_get("_G.reverse_d")

	-- plugin-a depends on plugin-b and plugin-c
	MiniTest.expect.equality(deps_a["https://github.com/owner/plugin-b"] ~= nil, true)
	MiniTest.expect.equality(deps_a["https://github.com/owner/plugin-c"] ~= nil, true)

	-- plugin-b and plugin-c both depend on plugin-d
	MiniTest.expect.equality(deps_b["https://github.com/owner/plugin-d"] ~= nil, true)
	MiniTest.expect.equality(deps_c["https://github.com/owner/plugin-d"] ~= nil, true)

	-- plugin-d has no dependencies
	MiniTest.expect.equality(deps_d, vim.NIL)

	-- plugin-d is a dependency of both plugin-b and plugin-c
	MiniTest.expect.equality(reverse_d["https://github.com/owner/plugin-b"] ~= nil, true)
	MiniTest.expect.equality(reverse_d["https://github.com/owner/plugin-c"] ~= nil, true)
end

return T
