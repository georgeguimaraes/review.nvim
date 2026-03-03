local M = {}

local config = require("review.config")
local comments = require("review.comments")
local export = require("review.export")

-- Track which buffers have keymaps set and what keys were mapped
local keymapped_buffers = {}

--- Check if a keymap is enabled (not false, nil, or empty string)
---@param key string|false|nil
---@return boolean
local function is_enabled(key)
  return key ~= nil and key ~= false and key ~= ""
end

--- Delete a keymap from a buffer if it exists
---@param bufnr number
---@param mode string
---@param lhs string|nil
local function del_keymap(bufnr, mode, lhs)
  if lhs and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
  end
end

--- Delete all tracked keymaps from a buffer
---@param bufnr number
local function clear_buffer_keymaps(bufnr)
  local tracked = keymapped_buffers[bufnr]
  if tracked then
    for _, entry in ipairs(tracked) do
      del_keymap(bufnr, entry[1], entry[2])
    end
  end
end

--- Format a keymap string for display
---@param key string
---@return string
local function format_key(key)
  -- Strip < > wrappers and make readable, but leave <leader> as-is
  local inner = key:match("^<(.+)>$")
  if not inner then return key end
  if inner:lower() == "leader" then return key end

  -- Handle modifiers: C- -> Ctrl-, S- stays as S-
  inner = inner:gsub("^C%-", "Ctrl-")
  return inner
end

--- Build help lines for a section
---@param entries {key: string, desc: string}[]
---@param title string
---@param lines string[]
---@param max_key_width number
local function add_section(entries, title, lines, max_key_width)
  if #entries == 0 then return end
  table.insert(lines, "")
  table.insert(lines, "  " .. title)
  for _, entry in ipairs(entries) do
    local padding = string.rep(" ", max_key_width - #entry.key + 3)
    table.insert(lines, "   " .. entry.key .. padding .. entry.desc)
  end
end

local help_popup = nil

local function close_help()
  if help_popup then
    help_popup:unmount()
    help_popup = nil
  end
end

local function show_help()
  if help_popup then
    close_help()
    return
  end

  local cfg = config.get()
  local km = cfg.keymaps
  local readonly = cfg.codediff.readonly

  local comment_entries = {}
  local nav_entries = {}
  local action_entries = {}

  local function entry(key_name, desc, tbl)
    local key = km[key_name]
    if not is_enabled(key) then return end
    table.insert(tbl, { key = format_key(key), desc = desc })
  end

  if readonly then
    entry("readonly_add", "Add comment", comment_entries)
    entry("readonly_edit", "Edit comment", comment_entries)
    entry("readonly_delete", "Delete comment", comment_entries)
    entry("readonly_add_file", "File-level comment", comment_entries)
  else
    entry("add_note", "Add note", comment_entries)
    entry("add_suggestion", "Add suggestion", comment_entries)
    entry("add_issue", "Add issue", comment_entries)
    entry("add_praise", "Add praise", comment_entries)
    entry("add_file_comment", "File comment", comment_entries)
    entry("edit_comment", "Edit comment", comment_entries)
    entry("delete_comment", "Delete comment", comment_entries)
  end

  entry("next_comment", "Next comment", nav_entries)
  entry("prev_comment", "Previous comment", nav_entries)
  entry("next_file", "Next file", nav_entries)
  entry("prev_file", "Previous file", nav_entries)
  entry("toggle_file_panel", "Toggle file panel", nav_entries)
  entry("list_comments", "List comments", nav_entries)

  entry("export_clipboard", "Export to clipboard", action_entries)
  entry("send_sidekick", "Send to sidekick", action_entries)
  entry("clear_comments", "Clear all", action_entries)
  entry("toggle_readonly", "Toggle readonly/edit", action_entries)
  entry("close", "Export & close review", action_entries)
  entry("show_help", "This help", action_entries)

  local all_entries = {}
  vim.list_extend(all_entries, comment_entries)
  vim.list_extend(all_entries, nav_entries)
  vim.list_extend(all_entries, action_entries)

  local max_key_width = 0
  for _, e in ipairs(all_entries) do
    max_key_width = math.max(max_key_width, #e.key)
  end

  local lines = {}
  add_section(comment_entries, "Comments", lines, max_key_width)
  add_section(nav_entries, "Navigation", lines, max_key_width)
  add_section(action_entries, "Actions", lines, max_key_width)
  table.insert(lines, "")

  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, #line)
  end

  local width = math.max(max_line_width + 2, 30)
  local height = #lines

  local Popup = require("nui.popup")
  help_popup = Popup({
    position = "50%",
    size = { width = width, height = height },
    border = {
      style = "rounded",
      text = {
        top = " Review Keymaps ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
  })

  help_popup:mount()

  local buf = help_popup.bufnr
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  vim.api.nvim_set_current_win(help_popup.winid)

  local map_opts = { noremap = true, nowait = true }
  help_popup:map("n", "?", close_help, map_opts)
  help_popup:map("n", "q", close_help, map_opts)
  help_popup:map("n", "<Esc>", close_help, map_opts)
end

---@param bufnr number
local function set_buffer_keymaps(bufnr)
  -- Clear existing keymaps first
  clear_buffer_keymaps(bufnr)

  local cfg = config.get()
  local km = cfg.keymaps
  local readonly = cfg.codediff.readonly
  local mapped = {}

  local function set(lhs, rhs, desc)
    if is_enabled(lhs) then
      vim.keymap.set("n", lhs, rhs, { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = desc })
      table.insert(mapped, { "n", lhs })
    end
  end

  local function set_visual(lhs, rhs, desc)
    if is_enabled(lhs) then
      vim.keymap.set("x", lhs, rhs, { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = desc })
      table.insert(mapped, { "x", lhs })
    end
  end

  -- Helper to jump to first hunk in current file
  local function jump_to_first_hunk()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then return end
    local tabpage = vim.api.nvim_get_current_tabpage()
    local session = lifecycle.get_session(tabpage)
    if not session or not session.stored_diff_result then return end
    local diff_result = session.stored_diff_result
    if #diff_result.changes == 0 then return end

    local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)
    local current_buf = vim.api.nvim_get_current_buf()
    local is_original = current_buf == orig_buf

    local first_hunk = diff_result.changes[1]
    local target_line = is_original and first_hunk.original.start_line or first_hunk.modified.start_line
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
  end

  -- File navigation helper
  local function navigate(direction)
    return function()
      local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
      if not ok then return end
      local tabpage = vim.api.nvim_get_current_tabpage()
      local explorer_obj = lifecycle.get_explorer(tabpage)
      if explorer_obj then
        require("codediff.ui.explorer")["navigate_" .. direction](explorer_obj)
        vim.defer_fn(jump_to_first_hunk, 100)
      end
    end
  end

  if readonly then
    -- READONLY MODE: Full review keymaps
    set(km.readonly_add, function() comments.add_with_menu() end, "Add comment (pick type)")
    set_visual(km.readonly_add, ":<C-u>lua require('review.comments').add_for_range()<CR>", "Add comment for selection")
    set(km.readonly_add_file, function() comments.file_comment() end, "File comment")
    set(km.readonly_delete, function() comments.delete_at_cursor() end, "Delete comment")
    set(km.readonly_edit, function() comments.edit_at_cursor() end, "Edit comment")
    set(km.list_comments, function() comments.list() end, "List all comments")
    set(km.export_clipboard, function() export.to_clipboard() end, "Export to clipboard")
    set(km.send_sidekick, function() export.to_sidekick() end, "Send to sidekick")
    set(km.clear_comments, function() require("review").clear() end, "Clear all comments")
    set(km.next_comment, function() comments.goto_next() end, "Next comment")
    set(km.prev_comment, function() comments.goto_prev() end, "Previous comment")
  else
    -- EDIT MODE: Typed add keymaps with visual mode support
    set(km.add_note, function() comments.add_at_cursor("note") end, "Add note")
    set_visual(km.add_note, ":<C-u>lua require('review.comments').add_for_range('note')<CR>", "Add note for selection")
    set(km.add_suggestion, function() comments.add_at_cursor("suggestion") end, "Add suggestion")
    set_visual(km.add_suggestion, ":<C-u>lua require('review.comments').add_for_range('suggestion')<CR>", "Add suggestion for selection")
    set(km.add_issue, function() comments.add_at_cursor("issue") end, "Add issue")
    set_visual(km.add_issue, ":<C-u>lua require('review.comments').add_for_range('issue')<CR>", "Add issue for selection")
    set(km.add_praise, function() comments.add_at_cursor("praise") end, "Add praise")
    set_visual(km.add_praise, ":<C-u>lua require('review.comments').add_for_range('praise')<CR>", "Add praise for selection")
    set(km.add_file_comment, function() comments.file_comment() end, "File comment")
    set(km.delete_comment, function() comments.delete_at_cursor() end, "Delete comment")
    set(km.edit_comment, function() comments.edit_at_cursor() end, "Edit comment")
  end

  -- Navigation and close - available in both modes (or edit mode only for nav)
  set(km.next_file, navigate("next"), "Next file")
  set(km.prev_file, navigate("prev"), "Previous file")
  set(km.toggle_file_panel, function()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then return end
    local tabpage = vim.api.nvim_get_current_tabpage()
    local explorer_obj = lifecycle.get_explorer(tabpage)
    if explorer_obj then
      require("codediff.ui.explorer").toggle_visibility(explorer_obj)
    end
  end, "Toggle file panel")
  set(km.close, function() require("review").close() end, "Close")
  set(km.toggle_readonly, function() require("review").toggle_readonly() end, "Toggle readonly mode")
  set(km.show_help, show_help, "Show help")

  keymapped_buffers[bufnr] = mapped
end

-- Autocmd group for keymaps
local augroup = nil

---@param tabpage number
function M.setup_keymaps(tabpage)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    vim.notify("codediff.ui.lifecycle not available", vim.log.levels.WARN, { title = "Review" })
    return
  end

  -- Clear old autocmds
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
  end
  augroup = vim.api.nvim_create_augroup("review_keymaps", { clear = true })

  -- Clear keymaps from all tracked buffers
  for bufnr in pairs(keymapped_buffers) do
    clear_buffer_keymaps(bufnr)
  end
  keymapped_buffers = {}

  -- Set keymaps on current buffer
  set_buffer_keymaps(vim.api.nvim_get_current_buf())

  -- Set up autocmd to apply keymaps when entering any buffer in this tabpage
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_tabpage() ~= tabpage then return end
      if not lifecycle.get_session(tabpage) then return end
      set_buffer_keymaps(vim.api.nvim_get_current_buf())
    end,
  })
end

-- Clear keymaps from all tracked buffers
function M.clear_keymaps()
  for bufnr in pairs(keymapped_buffers) do
    clear_buffer_keymaps(bufnr)
  end
  keymapped_buffers = {}
end

-- Cleanup augroup when session closes
function M.cleanup()
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
    augroup = nil
  end
  close_help()
  M.clear_keymaps()
end

M._test = {
  format_key = format_key,
  add_section = add_section,
  is_enabled = is_enabled,
}

return M
