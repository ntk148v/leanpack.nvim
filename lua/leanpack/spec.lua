---@module 'leanpack.spec'
local log = require("leanpack.log")
local state = require("leanpack.state")

local M = {}

-- Known fields in a plugin spec (leanpack + lazy.nvim compat)
local KNOWN_FIELDS = {
    -- Core fields
    src = true,
    name = true,
    version = true,
    dependencies = true,
    cond = true,
    lazy = true,
    priority = true,
    init = true,
    config = true,
    build = true,
    opts = true,
    main = true,
    enabled = true,
    optional = true,
    dev = true,
    -- Lazy triggers
    event = true,
    cmd = true,
    keys = true,
    ft = true,
    pattern = true,
    -- lazy.nvim compat
    sem_version = true,
    branch = true,
    tag = true,
    commit = true,
    dir = true,
    url = true,
    -- Internal (set by leanpack)
    _is_dependency = true,
    _import_order = true,
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
            log.warn(
                ("Unknown field '%s' in plugin spec for '%s'. Did you mean something else?"):format(
                    key,
                    spec.name or spec[1] or spec.src or "unknown"
                )
            )
            vim.schedule(function()
                vim.notify(
                    ("leanpack.nvim: Unknown field '%s' in plugin spec for '%s'. Did you mean something else?"):format(
                        key,
                        spec.name or spec[1] or spec.src or "unknown"
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

    -- Check if lua/ subdirectory exists
    local lua_dir = dir .. "/lua"
    if not is_dir(lua_dir) then
        return nil
    end

    -- Single scan: collect root .lua files and subdirectories with init.lua
    local root_files = {} -- normalized_name -> original_base_name
    local modules = {} -- normalized_name -> original_dir_name
    local module_list = {} -- ordered list of { normalized, original }
    local module_count = 0

    local fd = vim.uv.fs_scandir(lua_dir)
    if not fd then
        return nil
    end

    while true do
        local entry_name, entry_type = vim.uv.fs_scandir_next(fd)
        if not entry_name then
            break
        end
        if entry_type == "file" and entry_name:match("%.lua$") then
            local base = entry_name:match("^(.+)%.lua$")
            if base then
                root_files[normname(base)] = base
            end
        elseif entry_type == "directory" then
            local init_path = lua_dir .. "/" .. entry_name .. "/init.lua"
            if is_file(init_path) then
                local norm = normname(entry_name)
                modules[norm] = entry_name
                table.insert(module_list, { normalized = norm, original = entry_name })
                module_count = module_count + 1
            end
        end
    end

    -- Strategy 0: Exact root file match (e.g., lualine.lua)
    if root_files[normalized] then
        state.cache_main(name, dir, root_files[normalized])
        return root_files[normalized]
    end

    -- Strategy 1: Exact normalized module directory match
    if modules[normalized] then
        state.cache_main(name, dir, modules[normalized])
        return modules[normalized]
    end

    -- Strategy 2: Lowercase substring match
    local name_base = name:lower():gsub("%.nvim$", ""):gsub("%.vim$", "")
    for _, mod in ipairs(module_list) do
        local mod_base = mod.original:lower():gsub("%.nvim$", ""):gsub("%.vim$", "")
        if name_base:find(mod_base, 1, true) or mod_base:find(name_base, 1, true) then
            state.cache_main(name, dir, mod.original)
            return mod.original
        end
    end

    -- Strategy 3: Semantic match (split name parts, check against modules)
    local significant_parts = {}
    for part in name:gmatch("[^%.%-]+") do
        local lower = part:lower()
        if lower ~= "nvim" and lower ~= "neovim" and lower ~= "lua" then
            table.insert(significant_parts, lower)
        end
    end

    if #significant_parts > 0 and #significant_parts <= 3 then
        for _, mod in ipairs(module_list) do
            local mod_lower = mod.original:lower()
            for _, part in ipairs(significant_parts) do
                if mod_lower:find(part, 1, true) then
                    state.cache_main(name, dir, mod.original)
                    return mod.original
                end
            end
        end
    end

    -- Strategy 4: Single module directory fallback
    if module_count == 1 then
        local only = module_list[1].original
        state.cache_main(name, dir, only)
        return only
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
