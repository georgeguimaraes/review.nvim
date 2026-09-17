local M = {}

local store = require("review.store")
local config = require("review.config")

local function notify(msg, level)
  vim.notify(msg, level, { title = "review.nvim" })
end

---@return string
function M.generate_markdown()
  local all_comments = store.get_all()

  if #all_comments == 0 then
    return "No comments yet."
  end

  local lines = {}

  -- Header
  table.insert(lines, "I reviewed your code and have the following comments. Please address them.")
  table.insert(lines, "")
  table.insert(lines, "Comment types: ISSUE (problems to fix), SUGGESTION (improvements), NOTE (observations), PRAISE (positive feedback)")
  table.insert(lines, "Lines prefixed with ~ refer to the old (left) side of the diff.")
  table.insert(lines, "")

  -- Numbered list of comments
  for i, comment in ipairs(all_comments) do
    local type_name = string.upper(comment.type)
    local location
    local is_old = (comment.side or "new") == "old"
    if comment.line == 0 then
      location = comment.file
    elseif is_old then
      if comment.line_end and comment.line_end ~= comment.line then
        location = string.format("%s:~%d-~%d", comment.file, comment.line, comment.line_end)
      else
        location = string.format("%s:~%d", comment.file, comment.line)
      end
    elseif comment.line_end and comment.line_end ~= comment.line then
      location = string.format("%s:%d-%d", comment.file, comment.line, comment.line_end)
    else
      location = string.format("%s:%d", comment.file, comment.line)
    end
    table.insert(lines, string.format("%d. **[%s]** `%s` - %s", i, type_name, location, comment.text))
  end

  return table.concat(lines, "\n")
end

---Hand the export to its targets: the clipboard (export.clipboard) and the
---export.on_export callback. Every export path (C, :Review export, q) ends here.
---@return string|nil markdown nil when there is nothing to export
---@return number count
function M.deliver()
  local count = store.count()
  if count == 0 then
    return nil, 0
  end

  local markdown = M.generate_markdown()
  local cfg = config.get().export or {}

  if cfg.clipboard ~= false then
    vim.fn.setreg("+", markdown)
    vim.fn.setreg("*", markdown)
  end

  if type(cfg.on_export) == "function" then
    local ok, err = pcall(cfg.on_export, markdown, store.get_all())
    if not ok then
      notify("export.on_export failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end

  return markdown, count
end

---@param count number
---@return string
function M.delivered_message(count)
  local cfg = config.get().export or {}
  local targets = {}
  if cfg.clipboard ~= false then
    table.insert(targets, "clipboard")
  end
  if type(cfg.on_export) == "function" then
    table.insert(targets, "on_export")
  end
  local where = #targets > 0 and (" to " .. table.concat(targets, " and ")) or ""
  return string.format("Exported %d comment(s)%s", count, where)
end

function M.to_clipboard()
  local markdown, count = M.deliver()
  if not markdown then
    notify("No comments to export", vim.log.levels.WARN)
    return
  end

  -- Show content in a bottom split
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, "\n"))
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Remember current window to restore focus after closing
  local prev_win = vim.api.nvim_get_current_win()

  -- Open at bottom with appropriate height
  local line_count = #vim.split(markdown, "\n")
  local height = math.min(line_count + 1, 15)
  vim.cmd("botright " .. height .. "split")
  vim.api.nvim_win_set_buf(0, buf)

  -- Map q to close the preview and restore focus
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(0, true)
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end, { buffer = buf, nowait = true })

  notify(M.delivered_message(count), vim.log.levels.INFO)
end

function M.preview()
  local markdown = M.generate_markdown()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, "\n"))
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

function M.to_sidekick()
  local ok, sidekick_cli = pcall(require, "sidekick.cli")
  if not ok then
    notify("sidekick.nvim not installed", vim.log.levels.ERROR)
    return
  end

  local count = store.count()
  if count == 0 then
    notify("No comments to send", vim.log.levels.WARN)
    return
  end

  local markdown = M.generate_markdown()
  sidekick_cli.send({ msg = markdown })
  notify(string.format("Sent %d comment(s) to sidekick", count), vim.log.levels.INFO)
end

return M
