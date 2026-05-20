---@module 'leanpack.job'
local M = {}

---Run a vim.pack command in background
---@param type "install"|"update"
---@param payload string|table|nil
---@param on_complete function?
function M.run(type, payload, on_complete)
    local cmd = { vim.v.progpath, "--headless", "--noplugin" }
    local temp_file = nil

    if type == "install" then
        temp_file = vim.fn.tempname() .. ".json"
        local ok, err = pcall(vim.fn.writefile, { vim.json.encode(payload) }, temp_file)
        if not ok then
            vim.notify("Failed to write install specs to " .. temp_file .. ": " .. tostring(err), vim.log.levels.ERROR)
            return
        end

        local lua_cmd = string.format(
            [[
            local f = io.open('%s', 'r')
            if f then
                local data = f:read('*a')
                f:close()
                local specs = vim.json.decode(data)
                vim.pack.add(specs, {confirm=false})
            end
        ]],
            temp_file
        )

        table.insert(cmd, "-c")
        table.insert(cmd, string.format("lua %s", lua_cmd))
        table.insert(cmd, "-c")
        table.insert(cmd, "qa")
    elseif type == "update" then
        local arg = "nil"
        if payload then
            arg = ("vim.json.decode(%s)"):format(string.format("%q", vim.json.encode(payload)))
        end
        table.insert(cmd, "-c")
        table.insert(cmd, string.format("lua vim.pack.update(%s, {force=true})", arg))
        table.insert(cmd, "-c")
        table.insert(cmd, "qa")
    else
        vim.notify("Unknown job type: " .. tostring(type), vim.log.levels.ERROR)
        return
    end

    local function handle_output(data)
        for _, line in ipairs(data) do
            if line and line:match("vim%.pack:") then
                -- clean up carriage returns
                local clean = line:gsub("\r", ""):gsub("\n", "")
                if clean ~= "" then
                    vim.schedule(function()
                        vim.api.nvim_echo({ { clean, "Normal" } }, false, {})
                    end)
                end
            end
        end
    end

    vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            handle_output(data)
        end,
        on_stderr = function(_, data)
            handle_output(data)
        end,
        on_exit = function(_, code)
            if type == "install" and temp_file then
                pcall(vim.fn.delete, temp_file)
            end
            vim.schedule(function()
                if code == 0 then
                    vim.api.nvim_echo({ { "", "Normal" } }, false, {})
                else
                    vim.notify("Leanpack background job failed (code " .. tostring(code) .. ")", vim.log.levels.ERROR)
                end
                if on_complete then
                    on_complete(code == 0)
                end
            end)
        end,
    })
end

return M
