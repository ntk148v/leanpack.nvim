---@module 'leanpack.fs'
-- Safe filesystem operations for leanpack.nvim

local M = {}

function M.is_dir(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory" or false
end

function M.source_ftdetect_dir(dir)
    local fd = vim.uv.fs_scandir(dir)
    if not fd then
        return
    end

    local files = {}
    while true do
        local name, type = vim.uv.fs_scandir_next(fd)
        if not name then
            break
        end
        if type == "file" or type == "link" then
            if name:match("%.vim$") or name:match("%.lua$") then
                table.insert(files, dir .. "/" .. name)
            end
        end
    end

    table.sort(files)
    for _, file in ipairs(files) do
        vim.cmd("silent! source " .. vim.fn.fnameescape(file))
    end
end

return M
