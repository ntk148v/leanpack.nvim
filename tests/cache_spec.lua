local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
                vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
                _G.cache = require("leanpack.cache")
            ]])
        end,
        post_once = child.stop,
    },
})

T["stamp_for_dir()"] = MiniTest.new_set()

T["stamp_for_dir()"]["changes when lua directory mtime changes"] = function()
    child.lua([[
        local original_stat = vim.uv.fs_stat
        local mtimes = {
            ["/tmp/plugin/lua"] = { type = "directory", mtime = { sec = 10, nsec = 0 } },
        }

        vim.uv.fs_stat = function(path)
            return mtimes[path]
        end

        _G.first = cache.stamp_for_dir("/tmp/plugin")
        mtimes["/tmp/plugin/lua"] = { type = "directory", mtime = { sec = 20, nsec = 0 } }
        _G.second = cache.stamp_for_dir("/tmp/plugin")

        vim.uv.fs_stat = original_stat
    ]])

    MiniTest.expect.equality(child.lua_get("_G.first") ~= child.lua_get("_G.second"), true)
end

T["records"] = MiniTest.new_set()

T["records"]["returns nil when stamp mismatches"] = function()
    child.lua([[
        cache.set("main", "plugin:/tmp/plugin", "stamp-a", "plugin")
        _G.same = cache.get("main", "plugin:/tmp/plugin", "stamp-a")
        _G.diff = cache.get("main", "plugin:/tmp/plugin", "stamp-b")
    ]])

    MiniTest.expect.equality(child.lua_get("_G.same"), "plugin")
    MiniTest.expect.equality(child.lua_get("_G.diff"), vim.NIL)
end

return T
