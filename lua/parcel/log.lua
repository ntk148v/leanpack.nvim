---@module 'parcel.log'
local M = {}

local log_file = nil
local log_enabled = false

---Initialize logging
function M.init()
  local log_path = vim.fn.stdpath("log")
  log_file = log_path .. "/parcel.log"
  log_enabled = true
end

---Write a log message
---@param level string Log level (INFO, WARN, ERROR, DEBUG)
---@param message string Log message
function M.write(level, message)
  if not log_enabled or not log_file then
    return
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_line = string.format("[%s] [%s] %s\n", timestamp, level, message)

  local f = io.open(log_file, "a")
  if f then
    f:write(log_line)
    f:close()
  end
end

---Log info message
---@param message string
function M.info(message)
  M.write("INFO", message)
end

---Log warning message
---@param message string
function M.warn(message)
  M.write("WARN", message)
end

---Log error message
---@param message string
function M.error(message)
  M.write("ERROR", message)
end

---Log debug message
---@param message string
function M.debug(message)
  M.write("DEBUG", message)
end

---Get log file path
---@return string
function M.get_log_path()
  return log_file or ""
end

return M