---@module 'leanpack.log'
local M = {}

local log_file = nil
local log_enabled = false
local buffer = {}
local FLUSH_THRESHOLD = 20

---Flush buffered log messages to disk
local function flush()
    if #buffer == 0 or not log_file then
        return
    end
    local f = io.open(log_file, "a")
    if f then
        f:write(table.concat(buffer))
        f:close()
    end
    buffer = {}
end

---Initialize logging
function M.init()
    local log_path = vim.fn.stdpath("log")
    log_file = log_path .. "/leanpack.log"
    log_enabled = true

    -- Flush on exit to ensure no messages lost
    -- Defer to VimEnter so we don't block the very first setup steps
    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.api.nvim_create_autocmd("VimLeavePre", {
                callback = flush,
                once = true,
            })
        end,
        once = true,
    })
end

---Write a log message
---@param level string Log level (INFO, WARN, ERROR, DEBUG)
---@param message string Log message
function M.write(level, message)
    if not log_enabled or not log_file then
        return
    end

    -- Sanitize message to prevent log injection (remove newlines and control chars)
    local sanitized = message:gsub("[%c\r\n]+", " ")

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    buffer[#buffer + 1] = string.format("[%s] [%s] %s\n", timestamp, level, sanitized)

    if #buffer >= FLUSH_THRESHOLD then
        flush()
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

---Flush pending log messages (for manual flush)
M.flush = flush

---Get log file path
---@return string
function M.get_log_path()
    return log_file or ""
end

return M
