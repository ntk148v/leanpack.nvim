---@module 'parcel.lock'
local M = {}

---@class parcel.LockEntry
---@field branch string
---@field commit string
---@field src string

---@type table<string, parcel.LockEntry>
M.lock = { plugins = {} }

---Get the lockfile path
---@return string
local function get_lockfile_path()
  return vim.fn.stdpath("data") .. "/pack/vim-pack/lock"
end

---Load lockfile from disk
function M.load()
  local path = get_lockfile_path()
  if vim.fn.filereadable(path) == 1 then
    local ok, result = pcall(vim.json.decode, vim.fn.readfile(path))
    if ok and result then
      -- Handle vim.pack format with or without plugins wrapper
      if result.plugins then
        M.lock = result
      else
        M.lock = { plugins = result }
      end
    end
  end
end

---Save lockfile to disk
function M.save()
  local path = get_lockfile_path()
  -- Ensure directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":p:h"), "p")
  local data = vim.json.encode(M.lock)
  vim.fn.writefile({ data }, path)
end

---Update lock entry for a plugin
---@param name string
---@param branch string
---@param commit string
---@param src string
function M.update(name, branch, commit, src)
  M.lock.plugins[name] = { branch = branch, commit = commit, src = src }
end

---Get lock entry for a plugin
---@param name string
---@return parcel.LockEntry?
function M.get(name)
  return M.lock.plugins[name]
end

---Remove lock entry for a plugin
---@param name string
function M.remove(name)
  M.lock.plugins[name] = nil
end

return M
