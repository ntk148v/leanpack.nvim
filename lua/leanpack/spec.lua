---@module 'leanpack.spec'
local log = require("leanpack.log")
local state = require("leanpack.state")

local M = {}

-- Known fields in a plugin spec (leanpack + lazy.nvim compat)
local KNOWN_FIELDS = {
    -- Core fields
    src = true, name = true, version = true, dependencies = true, cond = true,
    lazy = true, priority = true, init = true, config = true, build = true,
    opts = true, main = true, enabled = true, optional = true, dev = true,
    -- Lazy triggers
    event = true, cmd = true, keys = true, ft = true, pattern = true,
    -- lazy.nvim compat
    sem_version = true, branch = true, tag = true, commit = true, dir = true,
    url = true,
    -- Internal (set by leanpack)
    _is_dependency = true, _import_order = true,
}

---Check if a path is a directory using vim.uv
---@param path string
---@return boolean
local function is_dir(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory" or false
end

---List files in a directory matching a pattern (simple glob)
---@param dir string
---@param pattern string Simple pattern like "*.lua"
---@return string[]
local function list_files(dir, pattern)
    local fd = vim.uv.fs_scandir(dir)
    if not fd then
        return {}
    end

    local files = {}
    local entry_pattern = nil
    if pattern then
        -- Convert glob pattern to regex-like for matching
        entry_pattern = pattern:gsub("%.", "%%."):gsub("*", ".*")
    end

    while true do
        local name, type = vim.uv.fs_scandir_next(fd)
        if not name then
            break
        end
        if type == "file" or type == "link" then
            if not entry_pattern or name:match(entry_pattern) then
                table.insert(files, dir .. "/" .. name)
            end
        end
    end
    return files
end

---List subdirectories in a directory
---@param dir string
---@return string[]
local function list_dirs(dir)
    local fd = vim.uv.fs_scandir(dir)
    if not fd then
        return {}
    end

    local dirs = {}
    while true do
        local name, type = vim.uv.fs_scandir_next(fd)
        if not name then
            break
        end
        if type == "directory" then
            table.insert(dirs, dir .. "/" .. name)
        end
    end
    return dirs
end

---Check if a file exists and is readable
---@param path string
---@return boolean
local function is_file(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "file" or false
end

---Expand short name to full URL
---@param short_name string e.g., "user/repo"
---@return string
local function expand_short_name(short_name)
    if short_name:match("^https?://") or short_name:match("^git@") then
        return short_name
    end
    return "https://github.com/" .. short_name
end

---Extract plugin name from source URL
---@param src string
---@return string
local function extract_name(src)
    -- Remove trailing .git and trailing slashes
    local name = src:gsub("%.git$", ""):gsub("/+$", "")

    -- Handle GitHub short names "user/repo"
    if not name:find("/") then
        return name
    end

    -- Extract last component
    name = name:match("([^/]+)$")

    -- Remove query strings and fragments
    if name then
        name = name:match("^([^?#]+)")
    end

    return name or src
end

---Resolve version from lazy.nvim compat fields
---@param spec leanpack.Spec
---@return string|vim.VersionRange?
local function resolve_version(spec)
    if spec.version then
        return spec.version
    end

    -- lazy.nvim compat: sem_version -> vim.version.range()
    if spec.sem_version then
        local ok, range = pcall(vim.version.range, spec.sem_version)
        if ok then
            return range
        end
        return spec.sem_version
    end

    -- lazy.nvim compat: branch, tag, commit -> version
    if spec.branch then
        return spec.branch
    end
    if spec.tag then
        return spec.tag
    end
    if spec.commit then
        return spec.commit
    end

    return nil
end

---Resolve source URL from spec
---@param spec leanpack.Spec
---@return string
local function resolve_src(spec)
    -- Dev mode: use local ~/projects/{plugin-name}
    if spec.dev then
        local name = spec.name or extract_name(spec[1] or spec.src or "")
        return vim.fn.expand("~/projects/" .. name)
    end

    if spec.src then
        return spec.src
    end
    if spec.url then
        return spec.url
    end
    if spec.dir then
        return vim.fn.expand(spec.dir) -- Expand ~ and environment variables
    end
    if spec[1] then
        return expand_short_name(spec[1])
    end

    error("Plugin spec must have src, url, dir, dev, or short name")
end

---Check if spec is enabled
---@param spec leanpack.Spec
---@return boolean
local function is_enabled(spec)
    if spec.enabled == nil then
        return true
    end
    if type(spec.enabled) == "function" then
        return spec.enabled()
    end
    return spec.enabled
end

---Validate spec for unknown fields
---@param spec leanpack.Spec
local function validate_spec(spec)
    for key in pairs(spec) do
        if type(key) == "string" and not KNOWN_FIELDS[key] then
            log.warn(("Unknown field '%s' in plugin spec for '%s'. Did you mean something else?"):format(
                key, spec.name or spec[1] or spec.src or "unknown"
            ))
            vim.schedule(function()
                vim.notify(
                    ("leanpack.nvim: Unknown field '%s' in plugin spec for '%s'. Did you mean something else?"):format(
                        key, spec.name or spec[1] or spec.src or "unknown"
                    ),
                    vim.log.levels.WARN
                )
            end)
        end
    end
end

---Normalize a plugin name for module matching (like lazy.nvim's Util.normname)
---@param name string
---@return string
local function normname(name)
    local ret = name
        :lower()
        :gsub("^n?vim%-", "") -- strip leading "vim-" or "nvim-"
        :gsub("%.n?vim$", "") -- strip trailing ".vim" or ".nvim"
        :gsub("[%.%-]lua", "") -- strip ".lua" or "-lua"
        :gsub("[^a-z]+", "") -- strip all non-lowercase-alpha characters
    return ret
end

---Detect the main module from plugin directory using normalized name
---@param name string Plugin name (e.g., "none-ls.nvim")
---@param dir string Plugin directory path
---@return string? detected_main_module
local function detect_main(name, dir)
    local normalized = normname(name)

    -- Expand ~ in directory path
    dir = vim.fn.expand(dir)

    -- Check cache first
    local cached = state.get_cached_main(name, dir)
    if cached then
        return cached
    end

    -- Check if directory exists
    if not is_dir(dir) then
        return nil
    end

    -- Search for Lua files in lua/ subdirectory
    local lua_dir = dir .. "/lua"
    if not is_dir(lua_dir) then
        return nil
    end

    -- Strategy 0: Check for direct .lua files in lua/ root (e.g., lualine.lua)
    local root_lua_files = list_files(lua_dir, "*.lua")
    for _, file_path in ipairs(root_lua_files) do
        local file_name = file_path:match("([^/]+)%.lua$")
        if file_name then
            local file_normalized = normname(file_name)
            if file_normalized == normalized then
                state.cache_main(name, dir, file_name)
                return file_name
            end
        end
    end

    -- Get the immediate subdirectories under lua/ to find module directories
    local module_paths = list_dirs(lua_dir)
    local module_names = {}
    for _, module_path in ipairs(module_paths) do
        local mod_name = module_path:match("([^/]+)$")
        if mod_name then
            table.insert(module_names, mod_name)
        end
    end

    -- Strategy 1: Try exact normalized name match
    local matches = {}
    for _, mod_name in ipairs(module_names) do
        local mod_normalized = normname(mod_name)
        if mod_normalized == normalized then
            local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
            if is_file(init_path) then
                table.insert(matches, mod_name)
            end
        end
    end

    if #matches == 1 then
        state.cache_main(name, dir, matches[1])
        return matches[1]
    end

    -- Strategy 2: Try lowercase substring matching
    local simple_lower = name:lower()
    for _, mod_name in ipairs(module_names) do
        local mod_lower = mod_name:lower()
        -- Remove .nvim/.vim suffixes for comparison
        local name_base = simple_lower:gsub("%.nvim$", ""):gsub("%.vim$", "")
        local mod_base = mod_lower:gsub("%.nvim$", ""):gsub("%.vim$", "")

        -- Check if one contains the other (after removing common suffixes)
        if name_base:find(mod_base, 1, true) or mod_base:find(name_base, 1, true) then
            local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
            if is_file(init_path) then
                state.cache_main(name, dir, mod_name)
                return mod_name
            end
        end
    end

    -- Strategy 3: Check for semantic matches (e.g., none-ls -> null-ls)
    -- Split name into parts and check if module shares significant parts
    local name_parts = {}
    for part in name:gmatch("[^%.%-]+") do
        table.insert(name_parts, part:lower())
    end

    -- Remove common filler words like "nvim", "lua", "neovim"
    local significant_parts = {}
    for _, part in ipairs(name_parts) do
        if not vim.tbl_contains({ "nvim", "neovim", "lua" }, part) then
            table.insert(significant_parts, part)
        end
    end

    -- If we have significant parts, try matching
    if #significant_parts > 0 then
        for _, mod_name in ipairs(module_names) do
            local mod_lower = mod_name:lower()
            local match_count = 0
            for _, part in ipairs(significant_parts) do
                if mod_lower:find(part, 1, true) then
                    match_count = match_count + 1
                end
            end
            -- If at least one significant part matches and it's a reasonable match
            if match_count >= 1 and #significant_parts <= 3 then
                local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
                if is_file(init_path) then
                    state.cache_main(name, dir, mod_name)
                    return mod_name
                end
            end
        end
    end

    -- Strategy 4: If only one module directory exists with init.lua, use it
    local single_matches = {}
    for _, mod_name in ipairs(module_names) do
        local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
        if is_file(init_path) then
            table.insert(single_matches, mod_name)
        end
    end

    if #single_matches == 1 then
        state.cache_main(name, dir, single_matches[1])
        return single_matches[1]
    end

    return nil
end

---Normalize a single spec
function M.normalize_spec(spec, defaults)
    if not is_enabled(spec) then
        return nil, ""
    end

    -- Validate for unknown fields
    validate_spec(spec)

    local src = resolve_src(spec)
    local normalized = {
        src = src,
        name = spec.name or extract_name(src),
        version = resolve_version(spec),
        dependencies = spec.dependencies,
        cond = spec.cond or (defaults and defaults.cond),
        lazy = spec.lazy,
        priority = spec.priority or 50,
        init = spec.init,
        config = spec.config,
        build = spec.build,
        opts = spec.opts,
        main = spec.main,
        event = M.normalize_list(spec.event),
        cmd = M.normalize_list(spec.cmd),
        keys = M.normalize_list(spec.keys),
        ft = M.normalize_list(spec.ft),
        pattern = spec.pattern,
        dev = spec.dev,
        optional = spec.optional,
    }

    return normalized, src
end

---Convert leanpack.Spec to vim.pack.Spec
---@param spec leanpack.Spec
---@return vim.pack.Spec
function M.to_pack_spec(spec)
    local pack_spec = {
        src = spec.src,
        name = spec.name,
    }

    if spec.version then
        pack_spec.version = spec.version
    end

    -- Store leanpack-specific data in vim.pack.Spec.data
    pack_spec.data = {
        leanpack = true,
        priority = spec.priority or 50,
    }

    -- Set load=false for lazy plugins to force them into opt/ directory
    -- This prevents automatic loading and enables lazy loading
    if spec.lazy == true then
        pack_spec.load = false
    end

    return pack_spec
end

---Resolve a field that can be a function or value
---@param field any
---@param plugin leanpack.Plugin?
---@return any
function M.resolve_field(field, plugin)
    if field == nil then
        return nil
    end
    if type(field) == "function" then
        return field(plugin)
    end
    return field
end

---Normalize string or list to list
---@param value string|string[]|nil
---@return string[]?
function M.normalize_list(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return { value }
    end
    return value
end

---Export utility functions for use by other modules
M.normname = normname
M.detect_main = detect_main

---Merge multiple specs for the same plugin
---@param specs leanpack.Spec[]
---@return leanpack.Spec merged_spec
function M.merge_specs(specs)
    if #specs == 0 then
        return {}
    end
    if #specs == 1 then
        return specs[1]
    end

    local merged = {}

    for _, spec in ipairs(specs) do
        -- Merge opts tables (function takes precedence)
        if spec.opts then
            if type(spec.opts) == "function" then
                merged.opts = spec.opts
            else
                merged.opts = vim.tbl_deep_extend("force", merged.opts or {}, spec.opts)
            end
        end

        -- Merge dependencies (append unique strings, all tables)
        if spec.dependencies then
            merged.dependencies = merged.dependencies or {}
            local deps = type(spec.dependencies) == "table" and spec.dependencies or { spec.dependencies }
            for _, dep in ipairs(deps) do
                if type(dep) ~= "string" or not vim.tbl_contains(merged.dependencies, dep) then
                    table.insert(merged.dependencies, dep)
                end
            end
        end

        -- Merge arrays (event, cmd, keys, ft) - inline append
        for _, key in ipairs({ "event", "cmd", "keys", "ft" }) do
            if spec[key] then
                merged[key] = vim.list_extend(merged[key] or {}, M.normalize_list(spec[key]) or {})
            end
        end

        -- Take first non-nil value for scalar fields
        for _, key in ipairs({
            "src",
            "name",
            "version",
            "cond",
            "lazy",
            "priority",
            "init",
            "config",
            "build",
            "main",
            "pattern",
            "dev",
            "optional",
        }) do
            if spec[key] ~= nil and merged[key] == nil then
                merged[key] = spec[key]
            end
        end
    end

    return merged
end

---Sort specs by priority (higher priority first)
---@param specs leanpack.Spec[]
---@return leanpack.Spec[]
function M.sort_by_priority(specs)
    table.sort(specs, function(a, b)
        local pa = a.priority or 50
        local pb = b.priority or 50
        return pa > pb
    end)
    return specs
end

return M
