local M = {}

local marks = require("review.marks")
local config = require("review.config")

---@type number|nil Current tabpage with active codediff session
local current_tabpage = nil

---@type number|nil Autocmd group for buffer events
local buf_augroup = nil

---Normalize a file path for consistent storage/lookup
---@param path string
---@return string
local function normalize_path(path)
  if not path then
    return path
  end
  -- Remove leading ./ if present
  path = path:gsub("^%./", "")
  -- Remove trailing slashes
  path = path:gsub("/+$", "")
  return path
end

---Set filetype for a buffer based on file path
---@param bufnr number
---@param path string|nil
local function set_buffer_filetype(bufnr, path)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not path or path == "" then
    return
  end

  -- Use Neovim's built-in filetype detection
  local ft = vim.filetype.match({ filename = path, buf = bufnr })
  if ft then
    vim.api.nvim_set_option_value("filetype", ft, { buf = bufnr })
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

---@return string|nil file path
---@return number|nil line number
---@return "old"|"new"|nil side
function M.get_cursor_position()
  local lifecycle = get_lifecycle()
  if not lifecycle or not current_tabpage then
    return nil, nil, nil
  end

  local sess = lifecycle.get_session(current_tabpage)
  if not sess then
    return nil, nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()

  -- Get paths from session
  local orig_path, mod_path = lifecycle.get_paths(current_tabpage)
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
    if bufname and bufname ~= "" then
      -- Strip codediff:// prefix if present
      if bufname:match("^codediff://") then
        file_path = mod_path or orig_path
      else
        file_path = vim.fn.fnamemodify(bufname, ":.")
      end
    end
  end

  if not file_path then
    return nil, nil, nil
  end

  -- Return relative path
  local git_ctx = lifecycle.get_git_context(current_tabpage)
  if git_ctx and git_ctx.git_root then
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local rel_path = abs_path:gsub("^" .. vim.pesc(git_ctx.git_root) .. "/", "")
    return normalize_path(rel_path), cursor[1], side
  end

  return normalize_path(vim.fn.fnamemodify(file_path, ":.")), cursor[1], side
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

-- Called when codediff session is created
function M.on_session_created(tabpage)
  current_tabpage = tabpage

  local lifecycle = get_lifecycle()
  if not lifecycle then
    return
  end

  local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)

  -- Set filetype for syntax highlighting (needed for commit reviews)
  local orig_path, mod_path = lifecycle.get_paths(tabpage)
  set_buffer_filetype(orig_buf, orig_path)
  set_buffer_filetype(mod_buf, mod_path)

  -- Make buffers readonly if configured
  local cfg = config.get()
  if cfg.codediff.readonly then
    if orig_buf and vim.api.nvim_buf_is_valid(orig_buf) then
      vim.api.nvim_set_option_value("modifiable", false, { buf = orig_buf })
      vim.api.nvim_set_option_value("readonly", true, { buf = orig_buf })
    end
    if mod_buf and vim.api.nvim_buf_is_valid(mod_buf) then
      vim.api.nvim_set_option_value("modifiable", false, { buf = mod_buf })
      vim.api.nvim_set_option_value("readonly", true, { buf = mod_buf })
    end
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
      local side = bufnr == ob and "old" or "new"
      marks.render_for_buffer(bufnr, side)
    end,
  })

  -- Initial render with delay for buffers to be ready
  vim.defer_fn(function()
    marks.render_for_buffer(orig_buf, "old")
    marks.render_for_buffer(mod_buf, "new")
  end, 100)
end

-- Called when codediff session is closed
function M.on_session_closed()
  current_tabpage = nil
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

  -- Re-render comments
  vim.defer_fn(function()
    marks.render_for_buffer(orig_buf, "old")
    marks.render_for_buffer(mod_buf, "new")
  end, 50)
end

return M
