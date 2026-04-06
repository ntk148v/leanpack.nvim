---@module 'parcel.keymap'
local M = {}

---Apply keymaps from keys spec
---@param keys parcel.KeysValue
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
---@param value parcel.KeysValue
---@return parcel.KeySpec[]
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

---Create lazy keymap that loads plugin on first press
---@param lhs string
---@param rhs string|fun()
---@param opts? { desc?: string, mode?: string|string[], remap?: boolean, nowait?: boolean }
function M.lazy_keymap(lhs, rhs, opts)
  opts = opts or {}
  local mode = opts.mode or "n"
  local modes = type(mode) == "table" and mode or { mode }

  for _, m in ipairs(modes) do
    vim.keymap.set(m, lhs, rhs, {
      desc = opts.desc,
      remap = opts.remap or false,
      nowait = opts.nowait or false,
    })
  end
end

return M