---@module 'leanpack.job'
local M = {}

-- Semaphore tracking per job lane
local running_lanes = {}

-- Set by leanpack.setup() from defaults.confirm
local confirm_enabled = false

---@param value boolean
function M.set_confirm(value)
    confirm_enabled = value
end

---Ask before fetching remote code. A headless Neovim cannot answer, so it proceeds.
---@param type string
---@param payload table|nil
---@return boolean
local function confirmed(type, payload)
    if not confirm_enabled or #vim.api.nvim_list_uis() == 0 then
        return true
    end
    local names = {}
    for _, item in ipairs(payload or {}) do
        names[#names + 1] = _G.type(item) == "table" and item.name or item
    end
    local target = #names > 0 and table.concat(names, ", ") or "all plugins"
    return vim.fn.confirm(("Leanpack: %s %s?"):format(type, target), "&Yes\n&No", 1) == 1
end

---Copy specs into a JSON-safe form
---@param specs vim.pack.Spec[]
---@return table[]
local function encode_specs(specs)
    return vim.tbl_map(function(s)
        local copy = vim.deepcopy(s)
        if _G.type(copy.version) == "table" then
            copy.version_range = tostring(s.version)
            copy.version = nil
        end
        return copy
    end, specs)
end

---Run a vim.pack command in background
---@param type "install"|"update"
---@param payload string|table|nil
---@param on_complete function?
---@return boolean true if job was started, false if blocked by concurrent job
function M.run(type, payload, on_complete)
    if running_lanes[type] then
        vim.notify(("A %q job is already running. Skipping duplicate."):format(type), vim.log.levels.WARN)
        return false
    end
    if not confirmed(type, payload) then
        return false
    end
    running_lanes[type] = true

    local function clear_lane()
        running_lanes[type] = nil
    end

    -- Wrap on_complete to clear lane
    local original_on_complete = on_complete
    on_complete = function(success)
        clear_lane()
        if original_on_complete then
            original_on_complete(success)
        end
    end

    -- -u NONE: the child must not run the user's init.lua, which would call setup() and spawn more jobs
    local cmd = { vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-i", "NONE" }
    local temp_file = nil
    local action

    if type == "install" then
        temp_file = vim.fn.tempname() .. ".json"
        local ok, err = pcall(vim.fn.writefile, { vim.json.encode(encode_specs(payload)) }, temp_file)
        if not ok then
            vim.notify("Failed to write install specs to " .. temp_file .. ": " .. tostring(err), vim.log.levels.ERROR)
            clear_lane()
            return false
        end

        -- JSON drops the VersionRange metatable, so the child rebuilds the range from its string form
        action = string.format(
            [[
            local specs = vim.json.decode(table.concat(vim.fn.readfile(%q), ''))
            for _, s in ipairs(specs) do
                if s.version_range then
                    s.version = vim.version.range(s.version_range)
                    s.version_range = nil
                end
            end
            vim.pack.add(specs, { confirm = false, load = false })
        ]],
            temp_file
        )
    elseif type == "update" then
        local arg = "nil"
        if payload then
            arg = ("vim.json.decode(%s)"):format(string.format("%q", vim.json.encode(payload)))
        end
        action = string.format("vim.pack.update(%s, { force = true })", arg)
    else
        vim.notify("Unknown job type: " .. tostring(type), vim.log.levels.ERROR)
        clear_lane()
        return false
    end

    -- A Lua error in -c does not change the exit code, so report it with :cquit
    table.insert(cmd, "-c")
    table.insert(
        cmd,
        ("lua local ok, err = pcall(function() %s end); if not ok then io.stderr:write('vim.pack: ' .. tostring(err) .. '\\n'); vim.cmd.cquit() end"):format(
            action
        )
    )
    table.insert(cmd, "-c")
    table.insert(cmd, "qa")

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

    local job_id = vim.fn.jobstart(cmd, {
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
                -- vim.pack reads its lockfile once, so without this it does not see the child's changes:
                -- add() would clone again and delete the plugin, and any write would drop the child's data.
                -- shortcut: the new instance reports all plugins as not active, use a vim.pack reload API if one appears
                package.loaded["vim.pack"] = nil
                vim.pack = require("vim.pack")

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

    if job_id <= 0 then
        clear_lane()
        vim.notify("Failed to start leanpack background job", vim.log.levels.ERROR)
        return false
    end

    return true
end

return M
