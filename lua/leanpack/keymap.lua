---@module 'leanpack.keymap'
local M = {}

---Apply keymaps from keys spec
---@param keys leanpack.KeysValue
function M.apply_keys(keys)
    local normalized = M.normalize_keys(keys)
    for _, key in ipairs(normalized) do
        local lhs = key[1]
        local rhs = key[2]
        local mode = key.mode or "n"
        local modes = type(mode) == "table" and mode or { mode }
        local desc = key.desc
        local remap = key.remap or false
        local nowait = key.nowait or false

        for _, m in ipairs(modes) do
            if rhs then
                vim.keymap.set(m, lhs, rhs, {
                    desc = desc,
                    remap = remap,
                    nowait = nowait,
                })
            end
        end
    end
end

---Normalize keys value to array of KeySpec
---@param value leanpack.KeysValue
---@return leanpack.KeySpec[]
function M.normalize_keys(value)
    if value == nil then
        return {}
    end

    -- Single string: "<leader>ff"
    if type(value) == "string" then
        return { { value } }
    end

    -- Array of strings or KeySpec
    local result = {}
    for _, item in ipairs(value) do
        if type(item) == "string" then
            table.insert(result, { item })
        elseif type(item) == "table" then
            table.insert(result, item)
        end
    end

    return result
end

return M
