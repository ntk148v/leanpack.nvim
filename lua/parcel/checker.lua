---@module 'parcel.checker'
local M = {}

M.running = false
M.updated = {}

local git = require("parcel.git")

---Check for updates for all installed plugins
function M.check()
  if M.running then
    return
  end
  M.running = true
  M.updated = {}

  local state = require("parcel.state")
  local packs = state.get_all_pack_specs()
  local i = 1

  local function process_next()
    if i > #packs then
      M.running = false
      M.report()
      return
    end

    local pack_spec = packs[i]
    i = i + 1

    local entry = state.get_entry(pack_spec.src)
    if entry and entry.plugin and entry.plugin.path and vim.fn.isdirectory(entry.plugin.path) == 1 then
      local plugin_path = entry.plugin.path
      git.get_info_async(plugin_path, function(commit, branch)
        if not commit or not branch then
          return process_next()
        end

        git.system_async({ "git", "-C", plugin_path, "fetch", "origin" }, function(fetch_res)
          if fetch_res.code ~= 0 then
            return process_next()
          end

          git.system_async({ "git", "-C", plugin_path, "rev-parse", "origin/" .. branch }, function(rev_res)
            if rev_res.code == 0 then
              local remote_commit = vim.trim(rev_res.stdout)
              if commit ~= remote_commit then
                table.insert(M.updated, ("%s: %s -> %s"):format(pack_spec.name, commit:sub(1, 8), remote_commit:sub(1, 8)))
              end
            end
            process_next()
          end)
        end)
      end)
    else
      process_next()
    end
  end

  process_next()
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
