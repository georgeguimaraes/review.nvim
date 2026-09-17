local M = {}

local marks = require("review.marks")
local config = require("review.config")
local normalize_path = require("review.utils").normalize_path

---@type number|nil Current tabpage with active codediff session
local current_tabpage = nil

---@type number|nil Autocmd group for buffer events
local buf_augroup = nil

---@type table<number, boolean> Tabpages whose modified pane was already focused once
local focused_tabpages = {}

---@type table<number, {modifiable: boolean, readonly: boolean}> Option values before review made a buffer readonly
local saved_buf_options = {}

---Make a buffer readonly for the review, remembering what it was before so
---on_session_closed can put it back (working-tree buffers outlive the review).
---@param bufnr number|nil
local function make_readonly(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not saved_buf_options[bufnr] then
    saved_buf_options[bufnr] = {
      modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr }),
      readonly = vim.api.nvim_get_option_value("readonly", { buf = bufnr }),
    }
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
end

---Restore modifiable/readonly on every buffer make_readonly touched.
function M.restore_buffer_options()
  for bufnr, opts in pairs(saved_buf_options) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_set_option_value("modifiable", opts.modifiable, { buf = bufnr })
      vim.api.nvim_set_option_value("readonly", opts.readonly, { buf = bufnr })
    end
  end
  saved_buf_options = {}
end

---Normalize a codediff path value to a plain string.
---codediff >= July 2026 returns a Path table ({ relative, absolute }) from
---lifecycle.get_paths; older versions return strings.
---@param path string|table|nil
---@return string|nil
local function to_path_string(path)
  if type(path) == "table" then
    if path.absolute and path.absolute ~= "" then
      return path.absolute
    end
    if path.relative and path.relative ~= "" then
      return path.relative
    end
    return nil
  end
  if path == "" then
    return nil
  end
  return path
end

---Set syntax highlighting for a buffer based on file path.
---Uses treesitter directly instead of setting filetype to avoid triggering
---FileType autocmds that other plugins (e.g. render-markdown.nvim) use to
---attach to buffers, which can interfere with review popups.
---@param bufnr number
---@param path string|table|nil
local function set_buffer_filetype(bufnr, path)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  path = to_path_string(path)
  if not path then
    return
  end

  local ft = vim.filetype.match({ filename = path, buf = bufnr })
  if ft then
    -- Try to use treesitter directly for syntax highlighting without
    -- triggering FileType autocmds from other plugins
    local lang = vim.treesitter.language.get_lang(ft) or ft
    local ts_ok = pcall(vim.treesitter.start, bufnr, lang)
    if not ts_ok then
      -- Fallback: set filetype if treesitter doesn't support the language
      vim.api.nvim_set_option_value("filetype", ft, { buf = bufnr })
    end
  end
end

---@return number|nil tabpage id
function M.get_current_tabpage()
  return current_tabpage
end

---@return table|nil codediff lifecycle module
local function get_lifecycle()
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil
  end
  return lifecycle
end

---@return table|nil codediff session
function M.get_session()
  if not current_tabpage then
    return nil
  end
  local lifecycle = get_lifecycle()
  if not lifecycle then
    return nil
  end
  return lifecycle.get_session(current_tabpage)
end

---Get codediff's explorer object for a tabpage, if the session has one.
---codediff < 4.0.6 exposed lifecycle.get_explorer; newer versions keep the
---explorer as the session's side panel (lifecycle.get_panel(tabpage).view).
---@param tabpage number
---@return table|nil explorer
function M.get_explorer(tabpage)
  local lifecycle = get_lifecycle()
  if not lifecycle then
    return nil
  end
  if lifecycle.get_explorer then
    return lifecycle.get_explorer(tabpage)
  end
  if lifecycle.get_panel then
    local panel = lifecycle.get_panel(tabpage)
    if panel and panel.name == "explorer" then
      return panel.view
    end
  end
  return nil
end

---Relativize a path against the git root for consistent storage/lookup
---@param path string|nil
---@param lifecycle table
---@param tabpage number
---@return string|nil
local function relativize_path(path, lifecycle, tabpage)
  path = to_path_string(path)
  if not path then
    return nil
  end
  local git_ctx = lifecycle.get_git_context(tabpage)
  if git_ctx and git_ctx.git_root then
    local abs = vim.fn.fnamemodify(path, ":p")
    return normalize_path(abs:gsub("^" .. vim.pesc(git_ctx.git_root) .. "/", ""))
  end
  return normalize_path(vim.fn.fnamemodify(path, ":."))
end

---@return string|nil file path
---@return number|nil line number
---@return "old"|"new"|nil side
---A comment target in an ordinary file buffer (no codediff involved):
---the file relative to the git root, side "new".
---@param bufnr? number
---@return string|nil file
function M.plain_buffer_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or name:match("^%a[%w+.-]*://") then
    return nil
  end
  return require("review.utils").relative_to_root(name)
end

function M.get_cursor_position()
  local lifecycle = get_lifecycle()
  local sess = lifecycle and current_tabpage and lifecycle.get_session(current_tabpage)
  if not sess then
    -- No review open: notes can still go on any file in the repo
    local file = M.plain_buffer_file()
    if not file then
      return nil, nil, nil
    end
    return file, vim.api.nvim_win_get_cursor(0)[1], "new"
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()

  -- Get paths from session
  local orig_path, mod_path = lifecycle.get_paths(current_tabpage)
  orig_path, mod_path = to_path_string(orig_path), to_path_string(mod_path)
  local orig_buf, mod_buf = lifecycle.get_buffers(current_tabpage)

  -- Determine which file we're on based on buffer
  local file_path
  local side
  if current_buf == orig_buf then
    file_path = orig_path
    side = "old"
  elseif current_buf == mod_buf then
    file_path = mod_path
    side = "new"
  else
    -- Try to get path from buffer name
    local bufname = vim.api.nvim_buf_get_name(current_buf)
    if bufname:match("^codediff://") then
      file_path = mod_path or orig_path
    else
      -- An ordinary file buffer while a review is open elsewhere
      local file = M.plain_buffer_file(current_buf)
      if not file then
        return nil, nil, nil
      end
      return file, cursor[1], "new"
    end
  end

  if not file_path then
    return nil, nil, nil
  end

  return relativize_path(file_path, lifecycle, current_tabpage), cursor[1], side
end

---@return string|nil file path
---@return number|nil start line
---@return number|nil end line
---@return "old"|"new"|nil side
function M.get_visual_range()
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local file, _, side = M.get_cursor_position()
  if not file then
    return nil, nil, nil, nil
  end

  return file, start_line, end_line, side
end

---@return number|nil original buffer
---@return number|nil modified buffer
function M.get_buffers()
  local lifecycle = get_lifecycle()
  if not lifecycle or not current_tabpage then
    return nil, nil
  end
  return lifecycle.get_buffers(current_tabpage)
end

---@return string|nil original path
---@return string|nil modified path
function M.get_paths()
  local lifecycle = get_lifecycle()
  if not lifecycle or not current_tabpage then
    return nil, nil
  end
  local orig_path, mod_path = lifecycle.get_paths(current_tabpage)
  return relativize_path(orig_path, lifecycle, current_tabpage),
    relativize_path(mod_path, lifecycle, current_tabpage)
end

-- Called when codediff session is created
function M.on_session_created(tabpage)
  current_tabpage = tabpage

  local lifecycle = get_lifecycle()
  if not lifecycle then
    return
  end

  local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)

  -- Set filetype for syntax highlighting (needed for commit reviews)
  local raw_orig_path, raw_mod_path = lifecycle.get_paths(tabpage)
  set_buffer_filetype(orig_buf, raw_orig_path)
  set_buffer_filetype(mod_buf, raw_mod_path)

  -- Make buffers readonly if configured
  if config.get().codediff.readonly then
    make_readonly(orig_buf)
    make_readonly(mod_buf)
  end

  -- Clear old autocmds
  if buf_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, buf_augroup)
  end
  buf_augroup = vim.api.nvim_create_augroup("review_buf_marks", { clear = true })

  -- Set up BufEnter autocmd to render marks when entering codediff buffers
  -- This ensures marks are rendered even if buffers weren't ready initially
  vim.api.nvim_create_autocmd("BufEnter", {
    group = buf_augroup,
    callback = function()
      if vim.api.nvim_get_current_tabpage() ~= current_tabpage then
        return
      end
      local bufnr = vim.api.nvim_get_current_buf()
      local ob, mb = lifecycle.get_buffers(current_tabpage)
      if bufnr ~= ob and bufnr ~= mb then
        return
      end
      marks.refresh()
    end,
  })

  -- Initial render with delay for buffers to be ready
  vim.defer_fn(function()
    marks.refresh()
  end, 100)

  -- Focus the modified (right) pane, but only on the first setup of this
  -- tabpage. CodeDiffOpen fires again on every file switch, and refocusing
  -- then steals the cursor from users who moved to the explorer.
  if not focused_tabpages[tabpage] then
    focused_tabpages[tabpage] = true
    vim.defer_fn(function()
      M._focus_modified_pane(lifecycle, tabpage)
    end, 150)
  end
end

function M._focus_modified_pane(lifecycle, tabpage)
  local cur_cfg = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
  if cur_cfg.relative ~= "" then
    return
  end
  local sess = lifecycle.get_session(tabpage)
  if sess and sess.modified_win and vim.api.nvim_win_is_valid(sess.modified_win) then
    vim.api.nvim_set_current_win(sess.modified_win)
  end
end

-- Called when codediff session is closed
function M.on_session_closed()
  if current_tabpage then
    focused_tabpages[current_tabpage] = nil
  end
  current_tabpage = nil
  M.restore_buffer_options()
  -- Clean up autocmds
  if buf_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, buf_augroup)
    buf_augroup = nil
  end
  require("review.keymaps").cleanup()
end

-- Called when file changes in explorer mode
function M.on_file_changed(tabpage)
  current_tabpage = tabpage

  local lifecycle = get_lifecycle()
  if not lifecycle then
    return
  end

  local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)

  -- Set syntax highlighting for the new file's buffers
  local raw_orig_path, raw_mod_path = lifecycle.get_paths(tabpage)
  set_buffer_filetype(orig_buf, raw_orig_path)
  set_buffer_filetype(mod_buf, raw_mod_path)

  -- Make buffers readonly if configured
  if config.get().codediff.readonly then
    make_readonly(orig_buf)
    make_readonly(mod_buf)
  end

  -- Re-render comments
  vim.defer_fn(function()
    marks.refresh()
  end, 50)
end

return M
