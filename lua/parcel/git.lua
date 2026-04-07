---@module 'parcel.git'
local M = {}

M.throttle = {
  enabled = false,
  rate = 2,        -- max requests per duration
  duration = 5000, -- duration in ms
}

M.last_call = 0
M.calls_in_period = 0

---Configure git throttling
---@param opts? { enabled?: boolean, rate?: number, duration?: number }
function M.setup(opts)
  if opts then
    if opts.enabled ~= nil then
      M.throttle.enabled = opts.enabled
    end
    if opts.rate ~= nil then
      M.throttle.rate = opts.rate
    end
    if opts.duration ~= nil then
      M.throttle.duration = opts.duration
    end
  end
end

---Throttle git calls to avoid rate limiting
---@param fn fun():any
---@return any
function M.throttled(fn)
  if not M.throttle.enabled then
    return fn()
  end

  local now = vim.loop.now()
  if now - M.last_call > M.throttle.duration then
    M.calls_in_period = 0
    M.last_call = now
  end

  if M.calls_in_period >= M.throttle.rate then
    local wait_time = M.throttle.duration - (now - M.last_call)
    if wait_time > 0 then
      vim.wait(wait_time)
    end
    M.calls_in_period = 0
    M.last_call = vim.loop.now()
  end

  M.calls_in_period = M.calls_in_period + 1
  return fn()
end

---Get git info for a plugin path
---@param path string
---@return string? commit, string? branch
function M.get_info(path)
  return M.throttled(function()
    local commit = vim.fn.system({ "git", "-C", path, "rev-parse", "HEAD" }):match("^%s*(.-)%s*$")
    local branch = vim.fn.system({ "git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD" }):match("^%s*(.-)%s*$")
    return commit, branch
  end)
end

return M
