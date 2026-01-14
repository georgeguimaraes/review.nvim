local M = {}

local store = require("diffnotes.store")

local function notify(msg, level)
  vim.notify(msg, level, { title = "Diffnotes" })
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
  table.insert(lines, "")

  -- Numbered list of comments
  for i, comment in ipairs(all_comments) do
    local type_name = string.upper(comment.type)
    table.insert(lines, string.format("%d. **[%s]** `%s:%d` - %s", i, type_name, comment.file, comment.line, comment.text))
  end

  return table.concat(lines, "\n")
end

function M.to_clipboard()
  local markdown = M.generate_markdown()
  local count = store.count()

  if count == 0 then
    notify("No comments to export", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", markdown)
  vim.fn.setreg("*", markdown)

  -- Show content in a bottom split
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, "\n"))
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_buf_set_name(buf, "[Diffnotes Export]")

  -- Open at bottom with appropriate height
  local line_count = #vim.split(markdown, "\n")
  local height = math.min(line_count + 1, 15)
  vim.cmd("botright " .. height .. "split")
  vim.api.nvim_win_set_buf(0, buf)

  -- Map q to close the preview
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(0, true)
  end, { buffer = buf, nowait = true })

  notify(string.format("Exported %d comment(s) to clipboard", count), vim.log.levels.INFO)
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

return M
