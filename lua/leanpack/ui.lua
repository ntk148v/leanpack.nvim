---@module 'leanpack.ui'
local state = require("leanpack.state")
local loader = require("leanpack.loader")

local M = {}
local ui_state = { buf = nil, win = nil, plugins = {}, filter = "" }
local NS = vim.api.nvim_create_namespace("leanpack-ui")

local function define_highlights()
  vim.api.nvim_set_hl(NS, "LeanpackHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackPlugin", { link = "String", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackCommit", { link = "Comment", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackSource", { link = "Comment", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackStatusLoaded", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackStatusPending", { link = "Comment", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackStatusLoading", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackLazy", { link = "Special", default = true })
  vim.api.nvim_set_hl(NS, "LeanpackKeybind", { link = "Keyword", default = true })
end

local function get_status(entry)
  if entry.load_status == "loaded" then
    return "●"
  elseif entry.load_status == "loading" then
    return "◐"
  else
    return "○"
  end
end

local function is_lazy(entry)
  if entry.merged_spec then
    return entry.merged_spec.event or entry.merged_spec.cmd or entry.merged_spec.keys or entry.merged_spec.ft
  end
  return false
end

-- Pad string to exact display width
local function pad_to_width(str, width)
  local display_width = vim.fn.strdisplaywidth(str)
  if display_width < width then
    return str .. string.rep(" ", width - display_width)
  end
  return str
end

local function format_content()
  local plugins = {}
  local max_name_width = 0
  local max_type_width = 7 -- "startup" is 7 chars
  local max_src_width = 0

  local filter_lower = ui_state.filter:lower()

  for src, entry in pairs(state.get_all_entries()) do
    if entry.merged_spec then
      local name = entry.merged_spec.name or src:match("([^/]+)$") or src

      -- Apply filter
      if filter_lower ~= "" then
        local name_match = name:lower():find(filter_lower, 1, true)
        local src_match = src:lower():find(filter_lower, 1, true)
        if not name_match and not src_match then
          goto continue
        end
      end

      table.insert(plugins, {
        name = name,
        status = get_status(entry),
        lazy = is_lazy(entry),
        src = src,
        entry = entry,
      })
      max_name_width = math.max(max_name_width, vim.fn.strdisplaywidth(name))
      max_src_width = math.max(max_src_width, vim.fn.strdisplaywidth(src))

      ::continue::
    end
  end
  table.sort(plugins, function(a, b) return a.name:lower() < b.name:lower() end)
  ui_state.plugins = plugins

  local lines = {}

  -- Header with filter info
  if ui_state.filter ~= "" then
    table.insert(lines, "  Filter: " .. ui_state.filter .. "  (" .. #plugins .. " plugins)")
  else
    table.insert(lines, "")
  end

  table.insert(lines, string.format("  %s  %s  %s  %s",
    " ",
    pad_to_width("Name", max_name_width),
    pad_to_width("Type", max_type_width),
    "Source"
  ))
  table.insert(lines, "")

  for _, p in ipairs(plugins) do
    local type_str = p.lazy and "lazy" or "startup"
    local row = string.format("  %s  %s  %s  %s",
      p.status,
      pad_to_width(p.name, max_name_width),
      pad_to_width(type_str, max_type_width),
      p.src
    )
    table.insert(lines, row)
  end

  local content_width = math.max(
    vim.fn.strdisplaywidth("  Name  Type  Source"),
    max_name_width + max_type_width + max_src_width + 12
  )

  return lines, content_width
end

local function apply_highlights(lines)
  vim.api.nvim_buf_clear_namespace(ui_state.buf, NS, 0, -1)

  vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "LeanpackHeader", 2, 0, -1)

  for i, plugin in ipairs(ui_state.plugins) do
    local line_num = i + 3
    local status_hl = plugin.status == "●" and "LeanpackStatusLoaded" or
        (plugin.status == "◐" and "LeanpackStatusLoading" or "LeanpackStatusPending")
    vim.api.nvim_buf_add_highlight(ui_state.buf, NS, status_hl, line_num, 2, 3)

    local name_start = 5
    local name_end = name_start + vim.fn.strdisplaywidth(plugin.name)
    vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "LeanpackPlugin", line_num, name_start, name_end)

    local type_start = name_start + vim.fn.strdisplaywidth(plugin.name) + 2
    if plugin.lazy then
      vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "LeanpackLazy", line_num, type_start, type_start + 4)
    end

    local src_start = type_start + 9
    vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "LeanpackSource", line_num, src_start, -1)
  end
end

local function get_plugin_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(ui_state.win)
  local idx = cursor[1] - 3
  if idx >= 1 and idx <= #ui_state.plugins then
    return ui_state.plugins[idx]
  end
  return nil
end

local function load_plugin()
  local p = get_plugin_at_cursor()
  if p then
    local spec = state.get_pack_spec(p.src)
    if spec then
      loader.load_plugin(spec)
      M.refresh()
      vim.notify("Loaded: " .. p.name)
    end
  end
end

local function update_plugin()
  local p = get_plugin_at_cursor()
  if p then
    vim.notify("Updating: " .. p.name)
    vim.pack.update({ p.name }, { force = true })
    vim.schedule(function()
      vim.cmd("redraw")
      vim.notify("Updated " .. p.name, vim.log.levels.INFO)
    end)
  end
end

local function update_all_plugins()
  local installed = vim.pack.get() or {}
  local total = #installed
  local current = 0

  vim.notify(string.format("Updating all plugins (0/%d)...", total))

  -- Create autocmd to track progress
  local augroup = vim.api.nvim_create_augroup("leanpack_update_progress", { clear = true })
  vim.api.nvim_create_autocmd("PackChanged", {
    group = augroup,
    callback = function(event)
      if event.data.kind == "update" then
        current = current + 1
        vim.notify(string.format("Updating plugins (%d/%d)...", current, total), vim.log.levels.INFO)
      end
    end,
  })

  vim.pack.update(nil, { force = true })
  vim.schedule(function()
    vim.api.nvim_del_augroup_by_id(augroup)
    vim.cmd("redraw")
    vim.notify(string.format("All plugins updated successfully (%d/%d)", total, total), vim.log.levels.INFO)
  end)
end

local function update_loaded_plugins()
  local loaded_names = {}
  for _, p in ipairs(ui_state.plugins) do
    if p.status == "●" then
      table.insert(loaded_names, p.name)
    end
  end

  if #loaded_names == 0 then
    vim.notify("No loaded plugins to update", vim.log.levels.INFO)
    return
  end

  vim.notify("Updating " .. #loaded_names .. " loaded plugins...")
  vim.pack.update(loaded_names, { force = true })
  vim.schedule(function()
    vim.cmd("redraw")
    vim.notify("Loaded plugins updated successfully", vim.log.levels.INFO)
  end)
end

local function build_plugin()
  local p = get_plugin_at_cursor()
  if p and p.entry.merged_spec and p.entry.merged_spec.build then
    local spec = state.get_pack_spec(p.src)
    if spec then loader.load_plugin(spec, { bang = true }) end
    require("leanpack.hooks").execute_build(p.entry.merged_spec.build, p.entry.plugin)
    vim.notify("Building: " .. p.name)
  elseif p then
    vim.notify("No build hook: " .. p.name, vim.log.levels.WARN)
  end
end

local function delete_plugin()
  local p = get_plugin_at_cursor()
  if p then
    vim.notify("Deleting: " .. p.name)
    vim.pack.del({ p.name }, { force = true })
    state.remove_plugin(p.name, p.src)
    M.refresh()
  end
end

local function prompt_filter()
  local ok, result = pcall(vim.fn.input, "Filter: ", ui_state.filter)
  if ok then
    ui_state.filter = result or ""
    M.refresh()
  end
end

local function clear_filter()
  ui_state.filter = ""
  M.refresh()
end

local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "leanpack-ui")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  return buf
end

local function create_window(buf, width)
  local height = math.min(4 + #ui_state.plugins, math.floor(vim.o.lines * 0.8))
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
    title = " 📦 leanpack.nvim ",
    title_pos = "center",
    footer = " <Enter>:load  u:update  U:update-all  b:build  d:delete  /:filter  <C-c>:clear  q:quit ",
    footer_pos = "center",
  })

  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)

  return win
end

local function set_keymaps()
  local opts = { buffer = ui_state.buf, silent = true }
  vim.keymap.set("n", "<CR>", load_plugin, opts)
  vim.keymap.set("n", "u", update_plugin, opts)
  vim.keymap.set("n", "U", update_all_plugins, opts)
  vim.keymap.set("n", "<C-u>", update_loaded_plugins, opts)
  vim.keymap.set("n", "b", build_plugin, opts)
  vim.keymap.set("n", "d", delete_plugin, opts)
  vim.keymap.set("n", "r", M.refresh, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  vim.keymap.set("n", "/", prompt_filter, opts)
  vim.keymap.set("n", "<C-c>", clear_filter, opts)
end

function M.refresh()
  if not ui_state.buf or not ui_state.win then return end
  define_highlights()
  local lines, width = format_content()
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", false)
  apply_highlights(lines)
end

function M.open()
  if vim.fn.getcmdwintype() ~= "" then
    vim.cmd("close")
  end
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end
  ui_state.buf = create_buffer()
  local lines, width = format_content()
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", false)
  ui_state.win = create_window(ui_state.buf, width)
  define_highlights()
  apply_highlights(lines)
  set_keymaps()
  local line_count = vim.api.nvim_buf_line_count(ui_state.buf)
  local cursor_line = math.min(4, line_count)
  vim.api.nvim_win_set_cursor(ui_state.win, { cursor_line, 0 })
end

function M.close()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    vim.api.nvim_win_close(ui_state.win, true)
  end
  ui_state.win = nil
  ui_state.buf = nil
end

function M.toggle()
  if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
    M.close()
  else
    M.open()
  end
end

return M
