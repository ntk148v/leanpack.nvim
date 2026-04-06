---@module 'parcel.ui'
local state = require("parcel.state")
local loader = require("parcel.loader")

local M = {}

-- UI state
local ui_state = {
  buf = nil,
  win = nil,
  plugins = {},
  selected_idx = 1,
}

---Get plugin status
---@param entry parcel.RegistryEntry
---@return string status
local function get_status(entry)
  if entry.load_status == "loaded" then
    return "●"
  elseif entry.load_status == "loading" then
    return "◐"
  else
    return "○"
  end
end

---Get plugin type (startup or lazy)
---@param entry parcel.RegistryEntry
---@return string
local function get_type(entry)
  if entry.merged_spec then
    if entry.merged_spec.event or entry.merged_spec.cmd or entry.merged_spec.keys or entry.merged_spec.ft then
      return "lazy"
    end
  end
  return "startup"
end

---Format plugin list
---@return string[]
local function format_plugins()
  local lines = {}
  local plugins = {}

  -- Header
  table.insert(lines, " Parcel.nvim - Plugin Manager")
  table.insert(lines, " ────────────────────────────")
  table.insert(lines, "")

  -- Collect plugins
  for src, entry in pairs(state.get_all_entries()) do
    if entry.merged_spec then
      local name = entry.merged_spec.name or src:match("([^/]+)$") or src
      local status = get_status(entry)
      local ptype = get_type(entry)
      table.insert(plugins, {
        name = name,
        status = status,
        type = ptype,
        src = src,
        entry = entry,
      })
    end
  end

  -- Sort by name
  table.sort(plugins, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  ui_state.plugins = plugins

  -- Format lines
  for i, plugin in ipairs(plugins) do
    local status = plugin.status
    local ptype = plugin.type == "lazy" and " [lazy]" or ""
    local line = string.format(" %s %s%s", status, plugin.name, ptype)
    table.insert(lines, line)
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, " ────────────────────────────")
  table.insert(lines, " ● loaded  ○ pending  ◐ loading")
  table.insert(lines, "")
  table.insert(lines, " <Enter> Load plugin")
  table.insert(lines, " <CR>    Load plugin")
  table.insert(lines, " u       Update plugin")
  table.insert(lines, " b       Build plugin")
  table.insert(lines, " d       Delete plugin")
  table.insert(lines, " r       Refresh")
  table.insert(lines, " q/<Esc> Close")

  return lines
end

---Create buffer
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "parcel-ui")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  return buf
end

---Create window
---@param buf number
local function create_window(buf)
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Plugins ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)

  return win
end

---Update buffer content
local function update_buffer()
  if not ui_state.buf then
    return
  end

  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", true)
  local lines = format_plugins()
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", false)

  -- Set highlights
  local ns = vim.api.nvim_create_namespace("parcel-ui")
  vim.api.nvim_buf_clear_namespace(ui_state.buf, ns, 0, -1)

  -- Highlight header
  vim.api.nvim_buf_add_highlight(ui_state.buf, ns, "Title", 0, 0, -1)

  -- Highlight plugins
  for i, plugin in ipairs(ui_state.plugins) do
    local line_idx = i + 3 -- Offset for header
    local status_hl = plugin.status == "●" and "DiagnosticOk" or "DiagnosticWarn"
    vim.api.nvim_buf_add_highlight(ui_state.buf, ns, status_hl, line_idx, 0, 2)
  end
end

---Get plugin at cursor
---@return table?
local function get_plugin_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(ui_state.win)
  local line_idx = cursor[1]
  local plugin_idx = line_idx - 3 -- Offset for header

  if plugin_idx >= 1 and plugin_idx <= #ui_state.plugins then
    return ui_state.plugins[plugin_idx]
  end

  return nil
end

---Load plugin at cursor
local function load_plugin()
  local plugin = get_plugin_at_cursor()
  if plugin then
    local pack_spec = state.get_pack_spec(plugin.src)
    if pack_spec then
      loader.load_plugin(pack_spec)
      update_buffer()
      vim.notify("Loaded: " .. plugin.name, vim.log.levels.INFO)
    end
  end
end

---Update plugin at cursor
local function update_plugin()
  local plugin = get_plugin_at_cursor()
  if plugin then
    vim.notify("Updating: " .. plugin.name, vim.log.levels.INFO)
    vim.pack.update({ plugin.name })
  end
end

---Build plugin at cursor
local function build_plugin()
  local plugin = get_plugin_at_cursor()
  if plugin then
    local entry = plugin.entry
    if entry.merged_spec and entry.merged_spec.build then
      local pack_spec = state.get_pack_spec(plugin.src)
      if pack_spec then
        loader.load_plugin(pack_spec, { bang = true })
      end
      local hooks = require("parcel.hooks")
      hooks.execute_build(entry.merged_spec.build, entry.plugin)
      vim.notify("Building: " .. plugin.name, vim.log.levels.INFO)
    else
      vim.notify("No build hook for: " .. plugin.name, vim.log.levels.WARN)
    end
  end
end

---Delete plugin at cursor
local function delete_plugin()
  local plugin = get_plugin_at_cursor()
  if plugin then
    vim.notify("Deleting: " .. plugin.name, vim.log.levels.WARN)
    vim.pack.del({ plugin.name }, { force = true })
    state.remove_plugin(plugin.name, plugin.src)
    update_buffer()
  end
end

---Set keymaps
local function set_keymaps()
  local opts = { buffer = ui_state.buf, silent = true }

  -- Navigation
  vim.keymap.set("n", "j", function()
    vim.api.nvim_feedkeys(vim.keycode("<Down>"), "n", false)
  end, opts)

  vim.keymap.set("n", "k", function()
    vim.api.nvim_feedkeys(vim.keycode("<Up>"), "n", false)
  end, opts)

  -- Actions
  vim.keymap.set("n", "<CR>", load_plugin, opts)
  vim.keymap.set("n", "<Enter>", load_plugin, opts)
  vim.keymap.set("n", "u", update_plugin, opts)
  vim.keymap.set("n", "b", build_plugin, opts)
  vim.keymap.set("n", "d", delete_plugin, opts)
  vim.keymap.set("n", "r", update_buffer, opts)

  -- Close
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

---Open UI
function M.open()
  -- Can't open floating window from command-line window
  if vim.fn.getcmdwintype() ~= "" then
    vim.notify("Cannot open UI from command-line window", vim.log.levels.WARN)
    return
  end

  -- Close existing window
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end

  ui_state.buf = create_buffer()
  ui_state.win = create_window(ui_state.buf)
  update_buffer()
  set_keymaps()

  -- Move cursor to first plugin
  vim.api.nvim_win_set_cursor(ui_state.win, { 4, 0 })
end

---Close UI
function M.close()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end
  ui_state.win = nil
  ui_state.buf = nil
end

---Toggle UI
function M.toggle()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    M.close()
  else
    M.open()
  end
end

return M