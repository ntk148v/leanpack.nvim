---@module 'parcel.ui'
local state = require("parcel.state")
local loader = require("parcel.loader")
local git = require("parcel.git")

local M = {}
local ui_state = { buf = nil, win = nil, plugins = {} }
local NS = vim.api.nvim_create_namespace("parcel-ui")

local function define_highlights()
  vim.api.nvim_set_hl(NS, "Header", { fg = "#8be9fd", bold = true })
  vim.api.nvim_set_hl(NS, "PluginName", { fg = "#f8f8f2", bold = true })
  vim.api.nvim_set_hl(NS, "PluginSource", { fg = "#6272a4" })
  vim.api.nvim_set_hl(NS, "StatusLoaded", { fg = "#50fa7b" })
  vim.api.nvim_set_hl(NS, "StatusPending", { fg = "#ffb86c" })
  vim.api.nvim_set_hl(NS, "StatusLoading", { fg = "#f1fa8c" })
  vim.api.nvim_set_hl(NS, "LazyTag", { fg = "#bd93f9" })
  vim.api.nvim_set_hl(NS, "Keybind", { fg = "#8be9fd", bold = true })
  vim.api.nvim_set_hl(NS, "Border", { fg = "#6272a4" })
end

local function get_status(entry)
  if entry.load_status == "loaded" then return "●"
  elseif entry.load_status == "loading" then return "◐"
  else return "○" end
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
  local max_content_width = 0
  
  for src, entry in pairs(state.get_all_entries()) do
    if entry.merged_spec then
      local name = entry.merged_spec.name or src:match("([^/]+)$") or src
      -- Get commit hash if available
      local commit = ""
      if entry.plugin and entry.plugin.path then
        local commit_hash = git.get_info(entry.plugin.path)
        if commit_hash then
          commit = commit_hash:sub(1, 7)
        end
      end
      -- Format name with commit
      local display_name = commit ~= "" and (name .. " (" .. commit .. ")") or name
      table.insert(plugins, {
        name = name,
        display_name = display_name,
        status = get_status(entry),
        lazy = is_lazy(entry),
        src = src,
        entry = entry,
      })
      local type_str = is_lazy(entry) and "lazy" or "startup"
      local row_content = string.format(" %s   %s %s %s", get_status(entry), display_name, type_str, src)
      max_content_width = math.max(max_content_width, vim.fn.strdisplaywidth(row_content))
    end
  end
  table.sort(plugins, function(a, b) return a.name:lower() < b.name:lower() end)
  ui_state.plugins = plugins

  local header_text = "📦 parcel.nvim • " .. #plugins .. " plugins"
  local footer_text = "<Enter>:load  u:update  b:build  d:delete  r:refresh  q:quit"
  local col_header_text = "      Name                           Type     Source"
  
  local content_width = math.max(
    vim.fn.strdisplaywidth(header_text),
    vim.fn.strdisplaywidth(col_header_text),
    max_content_width,
    vim.fn.strdisplaywidth(footer_text)
  )
  
  local width = math.min(content_width + 4, vim.o.columns - 4)
  local inner_width = width - 2
  
  local lines = {}
  local top = "┌" .. string.rep("─", inner_width) .. "┐"
  local sep = "├" .. string.rep("─", inner_width) .. "┤"
  local bot = "└" .. string.rep("─", inner_width) .. "┘"
  
  table.insert(lines, top)
  
  local header_left = math.floor((inner_width - vim.fn.strdisplaywidth(header_text)) / 2)
  local header_line = string.rep(" ", header_left) .. header_text
  table.insert(lines, "│" .. pad_to_width(header_line, inner_width) .. "│")
  
  table.insert(lines, sep)
  table.insert(lines, "│" .. pad_to_width(col_header_text, inner_width) .. "│")
  table.insert(lines, sep)
  
  for _, p in ipairs(plugins) do
    local type_str = p.lazy and "lazy" or "startup"
    local row_content = string.format(" %s   %-34s %-8s %s", p.status, p.display_name, type_str, p.src)
    table.insert(lines, "│" .. pad_to_width(row_content, inner_width) .. "│")
  end
  
  table.insert(lines, sep)
  
  local footer_left = math.floor((inner_width - vim.fn.strdisplaywidth(footer_text)) / 2)
  local footer_line = string.rep(" ", footer_left) .. footer_text
  table.insert(lines, "│" .. pad_to_width(footer_line, inner_width) .. "│")
  table.insert(lines, bot)
  
  return lines, width
end

local function apply_highlights(lines, width)
  vim.api.nvim_buf_clear_namespace(ui_state.buf, NS, 0, -1)
  local inner_width = width - 2
  
  vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "Header", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "Border", 3, 0, -1)
  
  for i = 5, 5 + #ui_state.plugins - 1 do
    local plugin = ui_state.plugins[i - 4]
    if plugin then
      local hl = plugin.status == "●" and "StatusLoaded" or (plugin.status == "◐" and "StatusLoading" or "StatusPending")
      vim.api.nvim_buf_add_highlight(ui_state.buf, NS, hl, i - 1, 2, 5)
      vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "PluginName", i - 1, 6, 40)
      if plugin.lazy then
        vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "LazyTag", i - 1, 41, 49)
      end
      vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "PluginSource", i - 1, 50, inner_width + 1)
    end
  end
  
  vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "Keybind", #lines - 2, 0, -1)
  
  for i = 0, #lines - 1 do
    local line = vim.api.nvim_buf_get_lines(ui_state.buf, i, i + 1, false)[1] or ""
    for j = 1, #line do
      local c = line:sub(j, j)
      if c == "│" or c == "┌" or c == "┐" or c == "└" or c == "┘" or c == "├" or c == "┤" or c == "─" then
        vim.api.nvim_buf_add_highlight(ui_state.buf, NS, "Border", i, j - 1, j)
      end
    end
  end
end

local function get_plugin_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(ui_state.win)
  local idx = cursor[1] - 4
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
    vim.pack.update({ p.name })
  end
end

local function build_plugin()
  local p = get_plugin_at_cursor()
  if p and p.entry.merged_spec and p.entry.merged_spec.build then
    local spec = state.get_pack_spec(p.src)
    if spec then loader.load_plugin(spec, { bang = true }) end
    require("parcel.hooks").execute_build(p.entry.merged_spec.build, p.entry.plugin)
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

local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "parcel-ui")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  return buf
end

local function create_window(buf, width)
  local height = math.min(6 + #ui_state.plugins, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "none",
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
  vim.keymap.set("n", "b", build_plugin, opts)
  vim.keymap.set("n", "d", delete_plugin, opts)
  vim.keymap.set("n", "r", M.refresh, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

function M.refresh()
  if not ui_state.buf or not ui_state.win then return end
  define_highlights()
  local lines, width = format_content()
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ui_state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ui_state.buf, "modifiable", false)
  apply_highlights(lines, width)
end

function M.open()
  -- Close command-line window if open
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
  apply_highlights(lines, width)
  set_keymaps()
  local line_count = vim.api.nvim_buf_line_count(ui_state.buf)
  local cursor_line = math.min(5, line_count)
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
