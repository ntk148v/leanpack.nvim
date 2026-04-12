---@module 'leanpack.spec'
local state = require("leanpack.state")

local M = {}

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
  -- Handle various URL formats
  local name = src:match("([^/]+)%.git$") -- https://github.com/user/name.git
  if name then return name end

  name = src:match("([^/]+)$") -- https://github.com/user/name
  if name then
    -- Remove query strings and fragments
    name = name:match("^([^?]+)")
    return name or src
  end

  return src
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

---Normalize a plugin name for module matching (like lazy.nvim's Util.normname)
---@param name string
---@return string
local function normname(name)
  local ret = name:lower()
    :gsub("^n?vim%-", "")     -- strip leading "vim-" or "nvim-"
    :gsub("%.n?vim$", "")     -- strip trailing ".vim" or ".nvim"
    :gsub("[%.%-]lua", "")    -- strip ".lua" or "-lua"
    :gsub("[^a-z]+", "")      -- strip all non-lowercase-alpha characters
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
  
  -- Check if directory exists
  if vim.fn.isdirectory(dir) ~= 1 then
    return nil
  end
  
  -- Search for Lua files in lua/ subdirectory
  local lua_dir = dir .. "/lua"
  if vim.fn.isdirectory(lua_dir) ~= 1 then
    return nil
  end
  
  -- Strategy 0: Check for direct .lua files in lua/ root (e.g., lualine.lua)
  local root_lua_files = vim.fn.glob(lua_dir .. "/*.lua", true, true)
  for _, file_path in ipairs(root_lua_files) do
    local file_name = file_path:match("([^/]+)%.lua$")
    if file_name then
      local file_normalized = normname(file_name)
      if file_normalized == normalized then
        return file_name
      end
    end
  end
  
  -- Get the immediate subdirectories under lua/ to find module directories
  local module_dirs = vim.fn.glob(lua_dir .. "/*", true, true)
  local module_names = {}
  for _, module_path in ipairs(module_dirs) do
    if vim.fn.isdirectory(module_path) == 1 then
      local mod_name = module_path:match("([^/]+)$")
      if mod_name then
        table.insert(module_names, mod_name)
      end
    end
  end
  
  -- Strategy 1: Try exact normalized name match
  local matches = {}
  for _, mod_name in ipairs(module_names) do
    local mod_normalized = normname(mod_name)
    if mod_normalized == normalized then
      local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
      if vim.fn.filereadable(init_path) == 1 then
        table.insert(matches, mod_name)
      end
    end
  end
  
  if #matches == 1 then
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
      if vim.fn.filereadable(init_path) == 1 then
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
        if vim.fn.filereadable(init_path) == 1 then
          return mod_name
        end
      end
    end
  end
  
  -- Strategy 4: If only one module directory exists with init.lua, use it
  local single_matches = {}
  for _, mod_name in ipairs(module_names) do
    local init_path = lua_dir .. "/" .. mod_name .. "/init.lua"
    if vim.fn.filereadable(init_path) == 1 then
      table.insert(single_matches, mod_name)
    end
  end
  
  if #single_matches == 1 then
    return single_matches[1]
  end
  
  return nil
end

---Normalize a single spec
function M.normalize_spec(spec, defaults)
  if not is_enabled(spec) then
    return nil, ""
  end

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
      "src", "name", "version", "cond", "lazy", "priority",
      "init", "config", "build", "main", "pattern", "dev", "optional"
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