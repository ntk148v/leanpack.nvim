---@module 'tests.migration_spec'
-- Integration tests for lazy.nvim -> leanpack.nvim spec migration
-- Verifies that common lazy.nvim spec patterns are correctly handled

local MiniTest = require("mini.test")
local helpers = require("tests.helpers")

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
				_G.deps = require("leanpack.deps")
				_G.state = require("leanpack.state")
				_G.lazy = require("leanpack.lazy")
			]])
        end,
        post_once = child.stop,
    },
})

-- ============================================================================
-- Short name format (lazy.nvim primary format)
-- ============================================================================

T["short name format"] = MiniTest.new_set()

T["short name format"]["'user/repo' expands to GitHub URL"] = function()
    child.lua([[
		_G.result, _G.src = spec.normalize_spec({ "nvim-treesitter/nvim-treesitter" })
	]])
    local result = child.lua_get("_G.result")
    local src = child.lua_get("_G.src")
    MiniTest.expect.equality(src, "https://github.com/nvim-treesitter/nvim-treesitter")
    MiniTest.expect.equality(result.name, "nvim-treesitter")
end

T["short name format"]["'user/plugin.nvim' extracts correct name"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "folke/tokyonight.nvim" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.name, "tokyonight.nvim")
    MiniTest.expect.equality(result.src, "https://github.com/folke/tokyonight.nvim")
end

T["short name format"]["handles dash in repo name"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "nvim-lua/plenary.nvim" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.name, "plenary.nvim")
end

-- ============================================================================
-- Version field (lazy.nvim semver pattern)
-- ============================================================================

T["version field"] = MiniTest.new_set()

T["version field"]["'^1.0' parses as semver range"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "^1.0" })
	]])
    local result = child.lua_get("_G.result")
    -- Should be a vim.VersionRange table, not a string
    MiniTest.expect.equality(type(result.version), "table")
end

T["version field"]["'1.*' parses as semver range"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "1.*" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(type(result.version), "table")
end

T["version field"]["'>=1.0.0' parses as semver range"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = ">=1.0.0" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(type(result.version), "table")
end

T["version field"]["branch name stays as literal string"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "main" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, "main")
end

T["version field"]["'v2.1.0' parses as semver range (valid semver)"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "v2.1.0" })
		_G.version_type = type(_G.result.version)
	]])
    -- v2.1.0 is valid semver, so vim.version.range() succeeds
    MiniTest.expect.equality(child.lua_get("_G.version_type"), "table")
end

T["version field"]["version = false yields nil"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = false })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, nil)
end

-- ============================================================================
-- sem_version field (leanpack-specific semver)
-- ============================================================================

T["sem_version field"] = MiniTest.new_set()

T["sem_version field"]["converts to vim.VersionRange"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", sem_version = ">=1.0.0" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(type(result.version), "table")
end

T["sem_version field"]["handles caret range"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", sem_version = "^2.0" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(type(result.version), "table")
end

-- ============================================================================
-- Branch/tag/commit fields (lazy.nvim compat)
-- ============================================================================

T["branch/tag/commit fields"] = MiniTest.new_set()

T["branch/tag/commit fields"]["branch maps to version"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", branch = "develop" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, "develop")
end

T["branch/tag/commit fields"]["tag maps to version"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", tag = "v1.0.0" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, "v1.0.0")
end

T["branch/tag/commit fields"]["commit maps to version"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", commit = "abc1234" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, "abc1234")
end

T["branch/tag/commit fields"]["version takes precedence over branch"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", version = "main", branch = "develop" })
	]])
    local result = child.lua_get("_G.result")
    -- version should be resolved first
    MiniTest.expect.equality(result.version, "main")
end

-- ============================================================================
-- Dependencies (lazy.nvim formats)
-- ============================================================================

T["dependencies"] = MiniTest.new_set()

T["dependencies"]["string dependency"] = function()
    child.lua([[
		local ctx = { defaults = {} }
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = { "nvim-lua/plenary.nvim" }
		}, ctx)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 1)
    MiniTest.expect.equality(result[1].src, "https://github.com/nvim-lua/plenary.nvim")
    MiniTest.expect.equality(result[1]._is_dependency, true)
end

T["dependencies"]["table dependency with opts"] = function()
    child.lua([[
		local ctx = { defaults = {} }
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = {
				{ "nvim-lua/plenary.nvim", opts = { foo = true } }
			}
		}, ctx)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 1)
    MiniTest.expect.equality(result[1].opts.foo, true)
end

T["dependencies"]["multi-string table (lazy.nvim shorthand)"] = function()
    child.lua([[
		local ctx = { defaults = {} }
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = {
				{ "owner/dep1", "owner/dep2", "owner/dep3" }
			}
		}, ctx)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 3)
end

T["dependencies"]["mixed string and table deps"] = function()
    child.lua([[
		local ctx = { defaults = {} }
		_G.result = deps.resolve_dependencies({
			src = "parent",
			dependencies = {
				"owner/simple-dep",
				{ "owner/table-dep", lazy = true }
			}
		}, ctx)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result, 2)
    MiniTest.expect.equality(result[1].src, "https://github.com/owner/simple-dep")
    MiniTest.expect.equality(result[2].src, "https://github.com/owner/table-dep")
    MiniTest.expect.equality(result[2].lazy, true)
end

T["dependencies"]["optional flag propagates from parent"] = function()
    child.lua([[
		local ctx = { defaults = {} }
		_G.result = deps.resolve_dependencies({
			src = "parent",
			optional = true,
			dependencies = { "owner/dep" }
		}, ctx)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result[1].optional, true)
end

-- ============================================================================
-- Lazy triggers (lazy.nvim patterns)
-- ============================================================================

T["lazy triggers"] = MiniTest.new_set()

T["lazy triggers"]["event = 'VeryLazy'"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo", event = "VeryLazy" })
		_G.is_lazy = lazy.is_lazy(_G.result)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.event, { "VeryLazy" })
    MiniTest.expect.equality(child.lua_get("_G.is_lazy"), true)
end

T["lazy triggers"]["event = { 'BufRead', 'BufNewFile' }"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			event = { "BufRead", "BufNewFile" }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result.event, 2)
end

T["lazy triggers"]["cmd = 'Telescope'"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"nvim-telescope/telescope.nvim",
			cmd = "Telescope"
		})
		_G.is_lazy = lazy.is_lazy(_G.result)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.cmd, { "Telescope" })
    MiniTest.expect.equality(child.lua_get("_G.is_lazy"), true)
end

T["lazy triggers"]["cmd = { 'NvimTreeToggle', 'NvimTreeFocus' }"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"nvim-tree/nvim-tree.lua",
			cmd = { "NvimTreeToggle", "NvimTreeFocus" }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result.cmd, 2)
end

T["lazy triggers"]["keys = 's' (flash.nvim pattern)"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "folke/flash.nvim", keys = "s" })
		_G.is_lazy = lazy.is_lazy(_G.result)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.keys, { "s" })
    MiniTest.expect.equality(child.lua_get("_G.is_lazy"), true)
end

T["lazy triggers"]["keys with complex spec table"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"folke/flash.nvim",
			keys = {
				{ "s", desc = "Flash" },
				{ "S", desc = "Flash Treesitter" },
			}
		})
		_G.keys_count = #_G.result.keys
	]])
    MiniTest.expect.equality(child.lua_get("_G.keys_count"), 2)
end

T["lazy triggers"]["ft = 'rust'"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "rust-lang/rust.vim", ft = "rust" })
		_G.is_lazy = lazy.is_lazy(_G.result)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.ft, { "rust" })
    MiniTest.expect.equality(child.lua_get("_G.is_lazy"), true)
end

T["lazy triggers"]["ft = { 'lua', 'vim', 'python' }"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/plugin",
			ft = { "lua", "vim", "python" }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result.ft, 3)
end

-- ============================================================================
-- Config/opts pattern (lazy.nvim auto-setup)
-- ============================================================================

T["config/opts pattern"] = MiniTest.new_set()

T["config/opts pattern"]["opts table is preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"windwp/nvim-autopairs",
			event = "InsertEnter",
			opts = { check_ts = true }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.opts.check_ts, true)
end

T["config/opts pattern"]["opts function is preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			opts = function() return { key = "value" } end
		})
		_G.opts_is_function = type(_G.result.opts) == "function"
	]])
    MiniTest.expect.equality(child.lua_get("_G.opts_is_function"), true)
end

T["config/opts pattern"]["config function is preserved"] = function()
    child.lua([[
		local my_config = function(plugin, opts) end
		_G.result = spec.normalize_spec({
			"user/repo",
			config = my_config
		})
		_G.has_config = _G.result.config ~= nil
	]])
    MiniTest.expect.equality(child.lua_get("_G.has_config"), true)
end

T["config/opts pattern"]["config = true triggers auto-setup"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			config = true,
			opts = { key = "value" }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.config, true)
    MiniTest.expect.equality(result.opts.key, "value")
end

-- ============================================================================
-- Init hook (lazy.nvim pre-load hook)
-- ============================================================================

T["init hook"] = MiniTest.new_set()

T["init hook"]["init function is preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			init = function() vim.g.loaded_plugin = true end
		})
		_G.has_init = _G.result.init ~= nil
	]])
    MiniTest.expect.equality(child.lua_get("_G.has_init"), true)
end

-- ============================================================================
-- Build hook (lazy.nvim post-install/update)
-- ============================================================================

T["build hook"] = MiniTest.new_set()

T["build hook"]["string build command preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"nvim-treesitter/nvim-treesitter",
			build = ":TSUpdate"
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.build, ":TSUpdate")
end

T["build hook"]["shell build command preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			build = "make"
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.build, "make")
end

T["build hook"]["function build hook preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			build = function(plugin) print("built") end
		})
		_G.build_is_function = type(_G.result.build) == "function"
	]])
    MiniTest.expect.equality(child.lua_get("_G.build_is_function"), true)
end

-- ============================================================================
-- Enabled/cond (conditional loading)
-- ============================================================================

T["enabled/cond"] = MiniTest.new_set()

T["enabled/cond"]["enabled = false disables plugin"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			enabled = false
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, vim.NIL)
end

T["enabled/cond"]["enabled function evaluated"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			enabled = function() return false end
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result, vim.NIL)
end

T["enabled/cond"]["cond function preserved"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"user/repo",
			cond = function() return vim.fn.has("nvim-0.10") == 1 end
		})
		_G.has_cond = _G.result.cond ~= nil
	]])
    MiniTest.expect.equality(child.lua_get("_G.has_cond"), true)
end

-- ============================================================================
-- Priority (loading order)
-- ============================================================================

T["priority"] = MiniTest.new_set()

T["priority"]["high priority for colorschemes"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"folke/tokyonight.nvim",
			lazy = false,
			priority = 1000,
		})
		_G.res_priority = _G.result.priority
		_G.res_lazy = _G.result.lazy
	]])
    MiniTest.expect.equality(child.lua_get("_G.res_priority"), 1000)
    MiniTest.expect.equality(child.lua_get("_G.res_lazy"), false)
end

T["priority"]["default priority is 50"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({ "user/repo" })
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.priority, 50)
end

-- ============================================================================
-- Dev mode (local development)
-- ============================================================================

T["dev mode"] = MiniTest.new_set()

T["dev mode"]["dev = true resolves to ~/projects/"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"myuser/my-plugin",
			dev = true
		})
	]])
    local result = child.lua_get("_G.result")
    local expected = vim.fn.expand("~/projects/my-plugin")
    MiniTest.expect.equality(result.src, expected)
end

T["dev mode"]["dir overrides default dev path"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"myuser/my-plugin",
			dir = "/custom/path/my-plugin"
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.src, "/custom/path/my-plugin")
end

-- ============================================================================
-- Multiple specs merging (same plugin declared in multiple files)
-- ============================================================================

T["spec merging"] = MiniTest.new_set()

T["spec merging"]["merges specs from multiple files"] = function()
    child.lua([[
		-- Simulate: one file declares the plugin, another adds keys
		_G.result = spec.merge_specs({
			{ src = "test", name = "test", event = "BufRead" },
			{ src = "test", name = "test", keys = { "<leader>t" } }
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(#result.event, 1)
    MiniTest.expect.equality(#result.keys, 1)
end

T["spec merging"]["opts tables merge deeply"] = function()
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

T["spec merging"]["function opts takes precedence over table"] = function()
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

-- ============================================================================
-- Real-world lazy.nvim spec patterns
-- ============================================================================

T["real-world patterns"] = MiniTest.new_set()

T["real-world patterns"]["telescope.nvim full spec"] = function()
    child.lua([[
		_G.result, _G.src = spec.normalize_spec({
			"nvim-telescope/telescope.nvim",
			branch = "0.1.x",
			dependencies = {
				"nvim-lua/plenary.nvim",
				{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
			},
			cmd = "Telescope",
		})
		-- Extract serializable fields (dependencies are nested tables)
		_G.res_src = _G.src
		_G.res_name = _G.result.name
		_G.res_version = _G.result.version
		_G.res_cmd = _G.result.cmd
		_G.res_dep_count = #_G.result.dependencies
	]])
    MiniTest.expect.equality(child.lua_get("_G.res_src"), "https://github.com/nvim-telescope/telescope.nvim")
    MiniTest.expect.equality(child.lua_get("_G.res_name"), "telescope.nvim")
    MiniTest.expect.equality(child.lua_get("_G.res_version"), "0.1.x")
    MiniTest.expect.equality(child.lua_get("_G.res_cmd"), { "Telescope" })
    MiniTest.expect.equality(child.lua_get("_G.res_dep_count"), 2)
end

T["real-world patterns"]["treesitter full spec"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"nvim-treesitter/nvim-treesitter",
			build = ":TSUpdate",
			event = { "BufReadPost", "BufNewFile" },
			opts = {
				highlight = { enable = true },
				indent = { enable = true },
			},
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.name, "nvim-treesitter")
    MiniTest.expect.equality(result.build, ":TSUpdate")
    MiniTest.expect.equality(#result.event, 2)
    MiniTest.expect.equality(result.opts.highlight.enable, true)
end

T["real-world patterns"]["colorscheme with priority"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"folke/tokyonight.nvim",
			lazy = false,
			priority = 1000,
			config = function() vim.cmd("colorscheme tokyonight") end,
		})
		-- Extract serializable fields
		_G.res_priority = _G.result.priority
		_G.res_lazy = _G.result.lazy
		_G.res_config_type = type(_G.result.config)
	]])
    MiniTest.expect.equality(child.lua_get("_G.res_priority"), 1000)
    MiniTest.expect.equality(child.lua_get("_G.res_lazy"), false)
    MiniTest.expect.equality(child.lua_get("_G.res_config_type"), "function")
end

T["real-world patterns"]["LSP plugin with ft trigger"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"rust-lang/rust.vim",
			ft = "rust",
		})
		_G.is_lazy = lazy.is_lazy(_G.result)
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.ft, { "rust" })
    MiniTest.expect.equality(child.lua_get("_G.is_lazy"), true)
end

T["real-world patterns"]["mini.nvim pattern with opts and config"] = function()
    child.lua([[
		_G.result = spec.normalize_spec({
			"echasnovski/mini.nvim",
			event = "VeryLazy",
			config = function()
				require("mini.pairs").setup()
			end,
		})
		-- Extract serializable fields
		_G.res_event = _G.result.event
		_G.res_config_type = type(_G.result.config)
	]])
    MiniTest.expect.equality(child.lua_get("_G.res_event"), { "VeryLazy" })
    MiniTest.expect.equality(child.lua_get("_G.res_config_type"), "function")
end

-- ============================================================================
-- to_pack_spec conversion
-- ============================================================================

T["to_pack_spec conversion"] = MiniTest.new_set()

T["to_pack_spec conversion"]["lazy plugin sets load = false"] = function()
    child.lua([[
		_G.result = spec.to_pack_spec({
			src = "https://github.com/user/repo",
			name = "repo",
			lazy = true,
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.load, false)
    MiniTest.expect.equality(result.data.leanpack, true)
end

T["to_pack_spec conversion"]["startup plugin has no load field"] = function()
    child.lua([[
		_G.result = spec.to_pack_spec({
			src = "https://github.com/user/repo",
			name = "repo",
			lazy = false,
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.load, nil)
end

T["to_pack_spec conversion"]["preserves version"] = function()
    child.lua([[
		_G.result = spec.to_pack_spec({
			src = "https://github.com/user/repo",
			name = "repo",
			version = "v1.0.0",
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(result.version, "v1.0.0")
end

T["to_pack_spec conversion"]["preserves semver range"] = function()
    child.lua([[
		local ok, range = pcall(vim.version.range, "^1.0")
		_G.result = spec.to_pack_spec({
			src = "https://github.com/user/repo",
			name = "repo",
			version = range,
		})
	]])
    local result = child.lua_get("_G.result")
    MiniTest.expect.equality(type(result.version), "table")
end

return T
