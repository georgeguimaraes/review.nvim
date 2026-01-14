local M = {}

local marks = require("review.marks")
local config = require("review.config")

---@type number|nil Current tabpage with active codediff session
local current_tabpage = nil

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
function M.get_cursor_position()
  local lifecycle = get_lifecycle()
  if not lifecycle or not current_tabpage then
    return nil, nil
  end

  local sess = lifecycle.get_session(current_tabpage)
  if not sess then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_buf = vim.api.nvim_get_current_buf()

  -- Get paths from session
  local orig_path, mod_path = lifecycle.get_paths(current_tabpage)
  local orig_buf, mod_buf = lifecycle.get_buffers(current_tabpage)

  -- Determine which file we're on based on buffer
  local file_path
  if current_buf == orig_buf then
    file_path = orig_path
  elseif current_buf == mod_buf then
    file_path = mod_path
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
    return nil, nil
  end

  -- Return relative path
  local git_ctx = lifecycle.get_git_context(current_tabpage)
  if git_ctx and git_ctx.git_root then
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local rel_path = abs_path:gsub("^" .. vim.pesc(git_ctx.git_root) .. "/", "")
    return rel_path, cursor[1]
  end

  return vim.fn.fnamemodify(file_path, ":."), cursor[1]
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

  -- Render comments for both buffers
  vim.defer_fn(function()
    marks.render_for_buffer(orig_buf)
    marks.render_for_buffer(mod_buf)
  end, 100)
end

-- Called when codediff session is closed
function M.on_session_closed()
  current_tabpage = nil
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
    marks.render_for_buffer(orig_buf)
    marks.render_for_buffer(mod_buf)
  end, 50)
end

return M
