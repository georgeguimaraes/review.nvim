local M = {}

local store = require("review.store")
local config = require("review.config")

local ns_id = vim.api.nvim_create_namespace("review")

---Normalize a file path to match how comments are stored
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

---@param text string
---@param type_name string
---@param hl string
---@return table[] virt_lines
local function build_comment_box(text, type_name, hl)
  local virt_lines = {}
  local text_lines = vim.split(text, "\n")

  local max_text_width = 0
  for _, text_line in ipairs(text_lines) do
    max_text_width = math.max(max_text_width, vim.fn.strdisplaywidth(text_line))
  end
  local header_text = string.format("[%s]", string.upper(type_name))
  local content_width = math.max(max_text_width, 20)

  local top_dashes = content_width - vim.fn.strdisplaywidth(header_text) + 1
  table.insert(virt_lines, { { "╭─" .. header_text .. string.rep("─", top_dashes) .. "╮", hl } })

  for _, text_line in ipairs(text_lines) do
    local padding = content_width - vim.fn.strdisplaywidth(text_line)
    table.insert(virt_lines, { { "│ " .. text_line .. string.rep(" ", padding) .. " │", hl } })
  end

  table.insert(virt_lines, { { "╰" .. string.rep("─", content_width + 2) .. "╯", hl } })
  return virt_lines
end

---@param bufnr number
---@param side? "old"|"new"
function M.render_for_buffer(bufnr, side)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if not bufname or bufname == "" then
    return
  end

  -- Extract file path, handling codediff:// virtual buffers
  local file
  if bufname:match("^codediff://") then
    -- Virtual buffer: extract path from URI
    -- Format: codediff://repo/path/to/file.lua?rev=xxx
    local path = bufname:match("^codediff://[^/]+/(.+)%?") or bufname:match("^codediff://[^/]+/(.+)$")
    if path then
      file = normalize_path(path)
    end
  else
    file = normalize_path(vim.fn.fnamemodify(bufname, ":."))
  end

  if not file then
    return
  end

  local comments = store.get_for_file(file, side)

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local cfg = config.get()

  for _, comment in ipairs(comments) do
    local type_info = cfg.comment_types[comment.type]
    local icon = type_info and type_info.icon or "●"
    local hl = type_info and type_info.hl or "ReviewSign"
    local line_hl = type_info and type_info.line_hl
    local name = type_info and type_info.name or comment.type
    local virt_lines = build_comment_box(comment.text, name, hl)

    if comment.line == 0 then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, 0, 0, {
        sign_text = icon,
        sign_hl_group = hl,
        virt_lines = virt_lines,
        virt_lines_above = true,
      })
    else

    local line_start = comment.line - 1
    local line_end_0 = (comment.line_end or comment.line) - 1
    local is_range = line_end_0 ~= line_start

    if line_start >= 0 then
      if is_range then
        -- Start line: sign + line highlight
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line_start, 0, {
          sign_text = icon,
          sign_hl_group = hl,
          line_hl_group = line_hl,
        })

        -- Middle lines: line highlight only
        for l = line_start + 1, line_end_0 - 1 do
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, l, 0, {
            line_hl_group = line_hl,
          })
        end

        -- Last line: line highlight + comment box
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line_end_0, 0, {
          line_hl_group = line_hl,
          virt_lines = virt_lines,
          virt_lines_above = false,
        })
      else
        -- Single line: sign + line highlight + comment box
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line_start, 0, {
          sign_text = icon,
          sign_hl_group = hl,
          line_hl_group = line_hl,
          virt_lines = virt_lines,
          virt_lines_above = false,
        })
      end
    end
    end
  end
end

function M.refresh()
  local ok, hooks = pcall(require, "review.hooks")
  if not ok then
    return
  end

  local orig_buf, mod_buf = hooks.get_buffers()
  if orig_buf then
    M.render_for_buffer(orig_buf, "old")
  end
  if mod_buf then
    M.render_for_buffer(mod_buf, "new")
  end
end

function M.clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    end
  end
end

return M
