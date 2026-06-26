---@module 'leanpack.lazy'
local deps = require("leanpack.deps")
local loader = require("leanpack.loader")
local spec_mod = require("leanpack.spec")
local state = require("leanpack.state")

local M = {}

local function replay_command(cmd_name, cmd_args)
    local cmd = {
        cmd = cmd_name,
        args = cmd_args.fargs,
        bang = cmd_args.bang,
        mods = cmd_args.smods,
    }

    if cmd_args.range and cmd_args.range > 0 then
        cmd.range = { cmd_args.line1, cmd_args.line2 }
    end
    if (not cmd.range) and cmd_args.count and cmd_args.count >= 0 then
        cmd.count = cmd_args.count
    end
    if cmd_args.reg and cmd_args.reg ~= "" then
        cmd.reg = cmd_args.reg
    end

    pcall(vim.api.nvim_cmd, cmd, {})
end

local function setup_ft_trigger(pack_spec, ft)
    local filetypes = spec_mod.normalize_list(ft) or {}
    vim.api.nvim_create_autocmd("FileType", {
        group = state.lazy_group,
        pattern = filetypes,
        once = true,
        callback = function(ev)
            require("leanpack.lazy_trigger.util").load_and_retrigger(pack_spec, ev.buf, "FileType")
        end,
    })
end

local function setup_cmd_triggers(registered_pack_specs)
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
    for cmd_name, pack_specs in pairs(cmd_to_packs) do
        if vim.fn.exists(":" .. cmd_name) == 2 then
            goto continue
        end
        vim.api.nvim_create_user_command(cmd_name, function(cmd_args)
            pcall(vim.api.nvim_del_user_command, cmd_name)
            for _, pack_spec in ipairs(pack_specs) do
                local entry = state.get_entry(pack_spec.src)
                if entry and entry.load_status == "pending" then
                    loader.load_plugin(pack_spec)
                end
            end
            replay_command(cmd_name, cmd_args)
        end, { nargs = "*", bang = true, range = true, bar = true })
        ::continue::
    end
end

---Check if a plugin should be lazy loaded
---@param spec leanpack.Spec
---@param plugin leanpack.Plugin?
---@param src? string
---@return boolean
function M.is_lazy(spec, plugin, src)
    -- Explicit lazy flag
    if spec.lazy ~= nil then
        return spec.lazy
    end

    -- Has lazy triggers
    local event = spec_mod.resolve_field(spec.event, plugin)
    local cmd = spec_mod.resolve_field(spec.cmd, plugin)
    local ft = spec_mod.resolve_field(spec.ft, plugin)
    local keys = spec_mod.resolve_field(spec.keys, plugin)

    if event or cmd or ft or (keys and #keys > 0) then
        return true
    end

    -- Is dependency of lazy plugin
    if src and deps.is_dependency_only(src) and spec.lazy == true then
        return true
    end

    return false
end

---Process lazy plugins and setup triggers
---@param ctx table Processing context
function M.process_lazy(ctx)
    -- Don't process if there are pending builds
    if state.has_pending_builds() then
        return
    end

    local event_handler = require("leanpack.lazy_trigger.event")
    local keys_handler = require("leanpack.lazy_trigger.keys")

    for _, pack_spec in ipairs(ctx.lazy_packs) do
        local entry = state.get_entry(pack_spec.src)
        if not entry or not entry.merged_spec then
            goto continue
        end

        local spec = entry.merged_spec
        local plugin = entry.plugin

        -- Setup event triggers
        local event = spec_mod.resolve_field(spec.event, plugin)
        if event then
            event_handler.setup(pack_spec, spec, event)
        end

        -- Setup filetype triggers
        local ft = spec_mod.resolve_field(spec.ft, plugin)
        if ft then
            setup_ft_trigger(pack_spec, ft)
        end

        ::continue::
    end

    -- Setup command triggers
    setup_cmd_triggers(ctx.lazy_packs)

    -- Setup keymap triggers
    keys_handler.setup(ctx.lazy_packs)

    -- Note: module trigger is already set up synchronously in init.lua:process_all()
    -- to ensure early autocmds (like BufReadPre) can intercept requires.
end

return M
