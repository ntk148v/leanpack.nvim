---@module 'parcel.spec'
local state = require("parcel.state")

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
---@param spec parcel.Spec
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
---@param spec parcel.Spec
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
---@param spec parcel.Spec
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

---Normalize a single spec
---@param spec parcel.Spec
---@param defaults? parcel.Config.Defaults
---@return parcel.Spec? normalized_spec, string src
function M.normalize_spec(spec, defaults)
  -- Check enabled
  if not is_enabled(spec) then
    return nil, ""
  end

  -- Resolve source
  local src = resolve_src(spec)
  local name = spec.name or extract_name(src)
  local version = resolve_version(spec)

  -- Build normalized spec
  local normalized = {
    src = src,
    name = name,
    version = version,
    dependencies = spec.dependencies,
    cond = spec.cond or (defaults and defaults.cond),
    lazy = spec.lazy,
    priority = spec.priority or 50,
    init = spec.init,
    config = spec.config,
    build = spec.build,
    opts = spec.opts,
    main = spec.main,
    event = spec.event,
    pattern = spec.pattern,
    cmd = spec.cmd,
    keys = spec.keys,
    ft = spec.ft,
    module = spec.module,
    dev = spec.dev,
    optional = spec.optional,
  }

  return normalized, src
end

---Convert parcel.Spec to vim.pack.Spec
---@param spec parcel.Spec
---@return vim.pack.Spec
function M.to_pack_spec(spec)
  local pack_spec = {
    src = spec.src,
    name = spec.name,
  }

  if spec.version then
    pack_spec.version = spec.version
  end

  -- Store parcel-specific data in vim.pack.Spec.data
  pack_spec.data = {
    parcel = true,
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
---@param plugin parcel.Plugin?
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

---Detect main module name from plugin name
---Simplified: relies on explicit `main` field or plugin name
---@param plugin parcel.Plugin
---@return string?
function M.detect_main(plugin)
  local name = plugin.spec.name
  if not name then
    return nil
  end

  -- Try plugin name directly first
  local ok = pcall(require, name)
  if ok then
    return name
  end

  -- Try common variations
  local variations = {
    name:gsub("%.nvim$", ""),
    name:gsub("^nvim%-", ""),
    name:gsub("%-nvim$", ""),
  }

  for _, variant in ipairs(variations) do
    if variant ~= name then
      ok = pcall(require, variant)
      if ok then
        return variant
      end
    end
  end

  return nil
end

---Merge multiple specs for the same plugin
---@param specs parcel.Spec[]
---@return parcel.Spec merged_spec
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
      "init", "config", "build", "main", "pattern", "module", "dev", "optional"
    }) do
      if spec[key] ~= nil and merged[key] == nil then
        merged[key] = spec[key]
      end
    end
  end

  return merged
end

---Sort specs by priority (higher priority first)
---@param specs parcel.Spec[]
---@return parcel.Spec[]
function M.sort_by_priority(specs)
  table.sort(specs, function(a, b)
    local pa = a.priority or 50
    local pb = b.priority or 50
    return pa > pb
  end)
  return specs
end

return M