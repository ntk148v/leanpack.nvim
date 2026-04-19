local state = require("leanpack.state")

local M = {}

-- Lazy-loaded core modules
local log_mod = nil
local loader_mod = nil
local spec_mod = nil

local function get_log()
    if not log_mod then log_mod = require("leanpack.log") end
    return log_mod
end

local function get_loader()
    if not loader_mod then loader_mod = require("leanpack.loader") end
    return loader_mod
end

local function get_spec_mod()
    if not spec_mod then spec_mod = require("leanpack.spec") end
    return spec_mod
end

-- Original loaders saved before we insert ours
local original_loaders = {}

-- Fast lookup: module name -> src (built at setup time)
local module_to_src = {}

-- Track modules we're currently loading to avoid recursion
local loading_modules = {}

---Custom loader that loads the plugin before requiring the module
local function leanpack_module_loader(modname)
    if loading_modules[modname] then
        -- On recursive calls, try the original loaders directly.
        for _, l in ipairs(original_loaders) do
            local ok, result = pcall(l, modname)
            if ok and type(result) == "function" then
                return result
            end
        end
        return nil
    end

    local src = module_to_src[modname]
    if not src then
        -- Try parent module if it's a sub-module (e.g., 'mason.settings' -> 'mason')
        local parts = vim.split(modname, ".", { plain = true })
        if #parts > 1 then
            src = module_to_src[parts[1]]
        end
    end

    if not src then
        return nil
    end

    local entry = state.get_entry(src)
    -- Only load if still pending
    if not entry or entry.load_status ~= "pending" then
        return nil
    end

    loading_modules[modname] = true

    get_log().info(("Module trigger: loading plugin %s for module %s"):format(src, modname))

    local pack_spec = state.get_pack_spec(src)
    if pack_spec then
        get_loader().load_plugin(pack_spec, { bang = true, lazy_trigger = true })
    end

    loading_modules[modname] = nil

    -- Try original loaders now that plugin is loaded
    for _, l in ipairs(original_loaders) do
        local ok, result = pcall(l, modname)
        if ok and type(result) == "function" then
            return result
        end
    end

    return nil
end

---Setup module trigger
---@param lazy_packs vim.pack.Spec[] List of lazy plugin specs
function M.setup(lazy_packs)
    local count = 0
    for _, pack_spec in ipairs(lazy_packs or {}) do
        local entry = state.get_entry(pack_spec.src)
        if entry and entry.merged_spec then
            local spec = entry.merged_spec
            local src = pack_spec.src

            -- 1. Register explicit main module
            if spec.main then
                module_to_src[spec.main] = src
                count = count + 1
            end

            -- 2. Scan plugin directory for top-level modules
            -- Use the path from vim.pack.get() if available, or guestimate
            local path = entry.plugin and entry.plugin.path
            if (not path or path == "") and pack_spec.name then
                -- Try to find it in the standard location if not yet set
                local opt_path = vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. pack_spec.name
                if vim.uv.fs_stat(opt_path) then
                    path = opt_path
                end
            end

            if path and path ~= "" then
                local lua_dir = path .. "/lua"
                local fd = vim.uv.fs_scandir(lua_dir)
                if fd then
                    while true do
                        local name, type = vim.uv.fs_scandir_next(fd)
                        if not name then break end
                        local mod = nil
                        if type == "file" and name:match("%.lua$") then
                            mod = name:sub(1, -5)
                        elseif type == "directory" then
                            mod = name
                        end
                        if mod and mod ~= "init" then
                            if not module_to_src[mod] then
                                module_to_src[mod] = src
                                count = count + 1
                            end
                        end
                    end
                end
            end

            -- 3. Fallback: use detect_main as a hint
            if not spec.main and path and path ~= "" then
                local detected = get_spec_mod().detect_main(pack_spec.name, path)
                if detected and not module_to_src[detected] then
                    module_to_src[detected] = src
                    count = count + 1
                end
            end
        end
    end

    -- Don't install loader if nothing to trigger
    if next(module_to_src) == nil then
        return
    end

    -- Save original loaders
    for i, l in ipairs(package.loaders or package.searchers) do
        original_loaders[i] = l
    end

    -- Insert our loader at position 2 (after preload, before file system)
    local loaders = package.loaders or package.searchers
    table.insert(loaders, 2, leanpack_module_loader)

    get_log().info("Module trigger loader installed for " .. tostring(count) .. " module(s)")
end

return M
