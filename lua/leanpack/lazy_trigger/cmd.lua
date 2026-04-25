---@module 'leanpack.lazy_trigger.cmd'
local loader = require("leanpack.loader")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

---Setup command-based lazy loading
---@param registered_pack_specs vim.pack.Spec[]
function M.setup(registered_pack_specs)
    local cmd_to_packs = {}

    for _, pack_spec in ipairs(registered_pack_specs) do
        local entry = state.get_entry(pack_spec.src)
        if entry and entry.merged_spec then
            local spec = entry.merged_spec
            local plugin = entry.plugin

            local cmd = spec_mod.resolve_field(spec.cmd, plugin)
            if cmd then
                local commands = spec_mod.normalize_list(cmd) or {}
                for _, c in ipairs(commands) do
                    if not cmd_to_packs[c] then
                        cmd_to_packs[c] = {}
                    end
                    table.insert(cmd_to_packs[c], pack_spec)
                end
            end
        end
    end

    -- Create user commands
    for cmd, pack_specs in pairs(cmd_to_packs) do
        -- Skip if command already exists (plugin may define it itself)
        if vim.fn.exists(":" .. cmd) == 2 then
            goto continue
        end

        vim.api.nvim_create_user_command(cmd, function(cmd_args)
            -- Delete the command first
            pcall(vim.api.nvim_del_user_command, cmd)

            -- Load all plugins that define this command
            for _, pack_spec in ipairs(pack_specs) do
                local entry = state.get_entry(pack_spec.src)
                if entry and entry.load_status == "pending" then
                    loader.load_plugin(pack_spec)
                end
            end

            -- Re-execute the command
            pcall(vim.api.nvim_cmd, {
                cmd = cmd,
                args = cmd_args.fargs,
            }, {})
        end, { nargs = "*" })
        ::continue::
    end
end

return M
