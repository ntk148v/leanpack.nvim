---@module 'tests.regression_spec'
-- Regression tests for failure handling in import, sync, job, load, and merge

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
            ]])
        end,
        post_once = child.stop,
    },
})

local eq = MiniTest.expect.equality

T["import"] = MiniTest.new_set()

T["import"]["failed spec file sets ctx.failed and keeps other files"] = function()
    child.lua([[
        local root = vim.fn.tempname() .. "/lua/x/lua"
        vim.fn.mkdir(root .. "/lua/rspec", "p")
        vim.fn.writefile({ "return { 'a/good' }" }, root .. "/lua/rspec/good.lua")
        vim.fn.writefile({ "return {" }, root .. "/lua/rspec/bad.lua")
        vim.fn.writefile({ "local x = 1" }, root .. "/lua/rspec/helper.lua")
        vim.fn.writefile({ "return { dir = '/tmp/d', opts = {} }" }, root .. "/lua/rspec/single.lua")
        vim.opt.rtp:prepend(root)
        vim.notify = function() end
        local ctx = { import_order = 0, seen = {} }
        local specs = require("leanpack.import").import_specs("rspec", ctx)
        _G.failed, _G.count = ctx.failed, #specs
    ]])
    eq(child.lua_get("_G.failed"), true)
    -- good.lua and single.lua; helper.lua has no specs
    eq(child.lua_get("_G.count"), 2)
end

T["sync"] = MiniTest.new_set()

T["sync"]["does not remove plugins after an import failure"] = function()
    child.lua([[
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/lua/plugins", "p")
        vim.fn.writefile({ "return {" }, root .. "/lua/plugins/bad.lua")
        vim.opt.rtp:prepend(root)
        vim.notify = function() end
        vim.pack.add = function() end
        _G.deleted = false
        vim.pack.del = function() _G.deleted = true end
        vim.uv.fs_scandir = function() return "h" end
        local done = false
        vim.uv.fs_scandir_next = function()
            if done then return nil end
            done = true
            return "installed-plugin", "directory"
        end
        require("leanpack").setup({ sync = true, performance = { rtp_prune = false, vim_loader = false } })
    ]])
    eq(child.lua_get("_G.deleted"), false)
end

T["job"] = MiniTest.new_set()

T["job"]["child ignores user config and keeps version ranges"] = function()
    child.lua([[
        local jobstart = vim.fn.jobstart
        vim.fn.jobstart = function(cmd) _G.cmd = cmd; return 1 end
        local range = vim.version.range("1.*")
        require("leanpack.job").run("install", { { src = "s", name = "n", version = range } })
        vim.fn.jobstart = jobstart
        local i = vim.fn.index(_G.cmd, "-u")
        _G.u_arg = _G.cmd[i + 2]
        for k, arg in ipairs(_G.cmd) do
            if arg == "-c" and _G.cmd[k + 1]:match("^lua ") then
                _G.chunk_ok = load(_G.cmd[k + 1]:sub(5)) ~= nil
                _G.has_cquit = _G.cmd[k + 1]:find("cquit", 1, true) ~= nil
                local file = _G.cmd[k + 1]:match('readfile%("([^"]+)"')
                _G.saved = vim.json.decode(table.concat(vim.fn.readfile(file), ""))[1]
            end
        end
        _G.rebuilt_has = vim.version.range(_G.saved.version_range):has("1.5.0")
        _G.rebuilt_excl = vim.version.range(_G.saved.version_range):has("2.0.0")
        _G.version_is_nil = _G.saved.version == nil
    ]])
    eq(child.lua_get("_G.u_arg"), "NONE")
    eq(child.lua_get("_G.chunk_ok"), true)
    eq(child.lua_get("_G.has_cquit"), true)
    eq(child.lua_get("_G.version_is_nil"), true)
    eq(child.lua_get("_G.rebuilt_has"), true)
    eq(child.lua_get("_G.rebuilt_excl"), false)
end

T["job"]["declined confirmation starts no job and clears the lane"] = function()
    child.lua([[
        local job = require("leanpack.job")
        job.set_confirm(true)
        vim.api.nvim_list_uis = function() return { {} } end
        vim.fn.confirm = function() return 2 end
        _G.started = 0
        vim.fn.jobstart = function() _G.started = _G.started + 1; return 1 end
        _G.first = job.run("update", { "p" })
        vim.fn.confirm = function() return 1 end
        _G.second = job.run("update", { "p" })
    ]])
    eq(child.lua_get("_G.first"), false)
    eq(child.lua_get("_G.second"), true)
    eq(child.lua_get("_G.started"), 1)
end

T["load"] = MiniTest.new_set()

local function add_plugin(src, fields)
    return ([[
        do
            local spec = vim.tbl_extend("force", { src = %q, name = %q }, %s)
            require("leanpack.state").set_entry(%q, {
                specs = { spec }, merged_spec = spec, load_status = "pending",
                plugin = { spec = { src = %q, name = %q }, path = "" },
            })
            require("leanpack.state").register_pack_spec({ src = %q, name = %q })
        end
    ]]):format(src, src, fields, src, src, src, src, src)
end

T["load"]["setup failure does not raise and marks only that plugin failed"] = function()
    child.lua(add_plugin("bad", "{ main = 'badmod', opts = {} }") .. [[
        package.preload.badmod = function() return { setup = function() error("boom") end } end
        vim.notify = function() end
        vim.cmd.packadd = function() end
    ]] .. add_plugin("throws", "{ opts = function() error('boom') end }") .. [[
        local loader = require("leanpack.loader")
        local state = require("leanpack.state")
        _G.ok = pcall(function()
            loader.load_plugin(state.get_pack_spec("bad"))
            loader.load_plugin(state.get_pack_spec("throws"))
        end)
    ]])
    eq(child.lua_get("_G.ok"), true)
end

T["load"]["packadd failure sets failed status instead of loading"] = function()
    child.lua(add_plugin("p", "{}") .. [[
        vim.notify = function() end
        vim.cmd = setmetatable({ packadd = function() error("E919") end }, { __index = vim.cmd })
        local state = require("leanpack.state")
        require("leanpack.loader").load_plugin(state.get_pack_spec("p"))
        _G.status = state.get_entry("p").load_status
    ]])
    eq(child.lua_get("_G.status"), "failed")
end

T["load"]["plugin waiting for install stays pending, with its dependent"] = function()
    child.lua(add_plugin("dep", "{}") .. add_plugin("parent", "{}") .. [[
        local state = require("leanpack.state")
        state.add_dependency("parent", "dep")
        state.get_entry("dep").installing = true
        _G.packadds = 0
        vim.cmd = setmetatable({ packadd = function() _G.packadds = _G.packadds + 1 end }, { __index = vim.cmd })
        require("leanpack.loader").load_plugin(state.get_pack_spec("parent"))
        _G.status = state.get_entry("parent").load_status
        _G.flag = state.get_entry("parent").load_after_install
    ]])
    eq(child.lua_get("_G.status"), "pending")
    eq(child.lua_get("_G.flag"), true)
    eq(child.lua_get("_G.packadds"), 0)
end

T["event"] = MiniTest.new_set()

T["event"]["a non-Buf event with no file name loads the plugin"] = function()
    child.lua(add_plugin("e", "{}") .. [[
        local state = require("leanpack.state")
        local spec = state.get_entry("e").merged_spec
        vim.cmd = setmetatable({ packadd = function() end }, { __index = vim.cmd })
        require("leanpack.lazy_trigger.event").setup(state.get_pack_spec("e"), spec, "User")
        vim.api.nvim_exec_autocmds("User", { pattern = "*" })
        _G.status = state.get_entry("e").load_status
    ]])
    eq(child.lua_get("_G.status"), "loaded")
end

T["merge"] = MiniTest.new_set()

T["merge"]["explicit values from a later mention win over dependency defaults"] = function()
    child.lua([[
        local spec_mod = require("leanpack.spec")
        local fn = function() end
        local merged = spec_mod.merge_specs({
            { src = "s", lazy = true, priority = 50, _is_dependency = true },
            { src = "s", lazy = false, priority = 1000, version = "1.0", _is_dependency = false },
        })
        _G.lazy, _G.priority = merged.lazy, merged.priority
        local mixed = spec_mod.merge_specs({
            { src = "s", opts = fn, keys = fn },
            { src = "s", opts = { a = 1 }, keys = { "k" } },
        })
        _G.opts_fn = mixed.opts == fn
        _G.keys_fn = mixed.keys == fn
    ]])
    eq(child.lua_get("_G.lazy"), false)
    eq(child.lua_get("_G.priority"), 1000)
    eq(child.lua_get("_G.opts_fn"), true)
    eq(child.lua_get("_G.keys_fn"), true)
end

return T
