---@module 'leanpack.lazy_trigger.keys'
local state = require("leanpack.state")
local loader = require("leanpack.loader")
local spec_mod = require("leanpack.spec")
local keymap = require("leanpack.keymap")

local M = {}

---Create unique key identifier
---@param lhs string
---@param mode string
---@return string
local function create_key_id(lhs, mode)
  return lhs .. "-" .. mode
end

---Setup keymap-based lazy loading
---@param registered_pack_specs vim.pack.Spec[]
function M.setup(registered_pack_specs)
  local key_to_info = {}

  for _, pack_spec in ipairs(registered_pack_specs) do
    local entry = state.get_entry(pack_spec.src)
    if entry and entry.merged_spec then
      local spec = entry.merged_spec
      local plugin = entry.plugin

      local keys_value = spec_mod.resolve_field(spec.keys, plugin)
      if keys_value then
        local keys = keymap.normalize_keys(keys_value)
        for _, key in ipairs(keys) do
          local lhs = key[1]
          local mode = key.mode or "n"
          local modes = spec_mod.normalize_list(mode) or { "n" }

          for _, m in ipairs(modes) do
            local key_id = create_key_id(lhs, m)
            if not key_to_info[key_id] then
              key_to_info[key_id] = {
                mode = m,
                pack_specs = {},
                key_spec = key,
              }
            end
            table.insert(key_to_info[key_id].pack_specs, pack_spec)
          end
        end
      end
    end
  end

  -- Create lazy keymaps
  for _, info in pairs(key_to_info) do
    local lhs = info.key_spec[1]
    local rhs = info.key_spec[2]
    local desc = info.key_spec.desc
    local remap = info.key_spec.remap or false
    local nowait = info.key_spec.nowait or false

    -- Skip if keymap already exists (plugin may define it itself)
    local existing = vim.api.nvim_get_keymap(info.mode, lhs)
    if next(existing) ~= nil then
      goto skip_keymap
    end

    vim.keymap.set(info.mode, lhs, function()
      -- Delete the keymap
      pcall(vim.keymap.del, info.mode, lhs)

      -- Load all plugins that define this keymap
      for _, pack_spec in ipairs(info.pack_specs) do
        loader.load_plugin(pack_spec)
      end

      -- Re-execute the keypress
      if rhs then
        if type(rhs) == "function" then
          rhs()
        else
          vim.api.nvim_feedkeys(vim.keycode(lhs), "m", false)
        end
      else
        vim.api.nvim_feedkeys(vim.keycode(lhs), "m", false)
      end
    end, {
      desc = desc,
      remap = remap,
      nowait = nowait,
    })

    ::skip_keymap::
  end
end

return M