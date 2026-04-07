---@module 'parcel.checker'
local M = {}

M.running = false
M.updated = {}

local git = require("parcel.git")

---Get git info for a plugin
---@param plugin_path string
---@return string? branch
---@return string? commit
local function get_git_info(plugin_path)
  if vim.fn.isdirectory(plugin_path) ~= 1 then
    return nil, nil
  end

  local commit, branch = git.get_info(plugin_path)
  return branch, commit
end

---Check for updates for a single plugin
---@param name string
---@param plugin_path string
---@param current_commit string
local function check_plugin_update(name, plugin_path, current_commit)
  -- Fetch and get latest commit on current branch
  local result = git.throttled(function()
    return vim.fn.system({ "git", "-C", plugin_path, "fetch", "origin" })
  end)
  if vim.v.shell_error ~= 0 then
    return
  end

  local commit, branch = git.get_info(plugin_path)
  if not branch or not commit then
    return
  end

  local remote_commit = git.throttled(function()
    return vim.fn.system({ "git", "-C", plugin_path, "rev-parse", "origin/" .. branch })
  end)
  if vim.v.shell_error ~= 0 then
    return
  end
  remote_commit = vim.trim(remote_commit)

  if current_commit ~= remote_commit then
    table.insert(M.updated, ("%s: %s -> %s"):format(name, current_commit:sub(1, 8), remote_commit:sub(1, 8)))
  end
end

---Check for updates for all installed plugins
function M.check()
  if M.running then
    return
  end
  M.running = true
  M.updated = {}

  local state = require("parcel.state")

  for _, pack_spec in ipairs(state.get_all_pack_specs()) do
    local entry = state.get_entry(pack_spec.src)
    if entry and entry.plugin and entry.plugin.path then
      local plugin_path = entry.plugin.path
      if vim.fn.isdirectory(plugin_path) == 1 then
        local branch, commit = get_git_info(plugin_path)
        if commit then
          check_plugin_update(pack_spec.name, plugin_path, commit)
        end
      end
    end
  end

  M.running = false
  M.report()
end

---Start the periodic checker
---@param frequency? number Seconds between checks, default 3600
function M.start(frequency)
  frequency = frequency or 3600
  vim.defer_fn(function()
    M.check()
    M.start(frequency) -- reschedule
  end, frequency * 1000)
end

---Report found updates via vim.notify
function M.report()
  if #M.updated > 0 then
    vim.notify("Plugin updates available:\n" .. table.concat(M.updated, "\n"), vim.log.levels.INFO)
  end
end

return M
