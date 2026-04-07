---@module 'parcel.async'
local M = {}

---@class parcel.AsyncTask
---@field fn fun()
---@field resolve fun()
---@field reject fun()

M.queue = {}
M.running = 0
M.concurrency = 4

---Set max concurrent tasks
---@param n number
function M.set_concurrency(n)
  M.concurrency = n
end

---Add task to queue
---@param fn fun():any
---@return Promise
function M.start(fn)
  return vim.Promise.new(function(resolve, reject)
    table.insert(M.queue, { fn = fn, resolve = resolve, reject = reject })
    M.process()
  end)
end

---Process next task in queue
function M.process()
  if M.running >= M.concurrency or #M.queue == 0 then
    return
  end

  M.running = M.running + 1
  local task = table.remove(M.queue, 1)

  vim.system(task.fn(), { text = true }):wait()
  M.running = M.running - 1
  task.resolve(nil)

  M.process()
end

return M
