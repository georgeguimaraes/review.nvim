local M = {}

local Popup = require("nui.popup")

---@class Commit
---@field hash string
---@field short_hash string
---@field message string
---@field author string
---@field date string

---@type Commit[]
local commits = {}
---@type table<string, boolean>
local selected = {}
---@type any
local popup = nil

local function get_git_root()
  local result = vim.fn.systemlist("git rev-parse --show-toplevel")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return result[1]
end

local function fetch_commits(limit)
  limit = limit or 50
  local git_root = get_git_root()
  if not git_root then
    return {}
  end

  -- Format: hash|short_hash|author|relative_date|subject
  local format = "%H|%h|%an|%cr|%s"
  local cmd = string.format("git -C %s log --format='%s' -n %d", vim.fn.shellescape(git_root), format, limit)
  local result = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 then
    return {}
  end

  local parsed = {}
  for _, line in ipairs(result) do
    local parts = vim.split(line, "|", { plain = true })
    if #parts >= 5 then
      table.insert(parsed, {
        hash = parts[1],
        short_hash = parts[2],
        author = parts[3],
        date = parts[4],
        message = table.concat({ unpack(parts, 5) }, "|"), -- message may contain |
      })
    end
  end

  return parsed
end

local ns_id = nil

local function format_line(commit)
  local marker = selected[commit.hash] and "[x]" or "[ ]"
  local line = string.format("%s %s %s (%s, %s)", marker, commit.short_hash, commit.message, commit.author, commit.date)
  if #line > 120 then
    line = line:sub(1, 117) .. "..."
  end
  return line
end

local function render_lines()
  if not popup then
    return
  end

  local buf = popup.bufnr
  local lines = {}

  for _, commit in ipairs(commits) do
    table.insert(lines, format_line(commit))
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  ns_id = vim.api.nvim_create_namespace("review_picker")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for i, commit in ipairs(commits) do
    if selected[commit.hash] then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "Visual", i - 1, 0, -1)
    end
  end
end

local function update_line(line_num)
  if not popup then return end
  local buf = popup.bufnr
  local commit = commits[line_num]
  if not commit then return end

  -- Update just this line's text
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { format_line(commit) })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Update highlight
  if ns_id then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, line_num - 1, line_num)
    if selected[commit.hash] then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "Visual", line_num - 1, 0, -1)
    end
  end
end

local function toggle_selection()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local commit = commits[line_num]
  if commit then
    selected[commit.hash] = not selected[commit.hash]
    update_line(line_num)
  end
end

local function select_none()
  selected = {}
  render_lines()
end

local function get_selected_commits()
  local result = {}
  -- Maintain order from commits list (newest first from git log)
  for _, commit in ipairs(commits) do
    if selected[commit.hash] then
      table.insert(result, commit)
    end
  end
  return result
end

local function close_picker()
  if popup then
    popup:unmount()
    popup = nil
  end
  commits = {}
  selected = {}
end

local function confirm_selection(callback)
  local selected_commits = get_selected_commits()
  close_picker()

  if #selected_commits == 0 then
    -- No commits selected, open regular codediff (staged + unstaged)
    callback(nil, nil)
    return
  end

  -- Git log returns newest first, so:
  -- - First selected = newest
  -- - Last selected = oldest
  local newest = selected_commits[1]
  local oldest = selected_commits[#selected_commits]

  -- Use ^ on oldest to include its changes
  callback(oldest.hash .. "^", newest.hash)
end

function M.open(callback)
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  commits = fetch_commits(50)
  selected = {}

  if #commits == 0 then
    vim.notify("No commits found", vim.log.levels.WARN, { title = "Review" })
    return
  end

  local width = math.min(120, vim.o.columns - 10)
  local height = math.min(20, #commits + 2, vim.o.lines - 10)

  popup = Popup({
    position = "50%",
    size = {
      width = width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = " Select commits to review ",
        top_align = "center",
        bottom = " <Space> select | <CR> confirm | q quit | n clear ",
        bottom_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
    win_options = {
      cursorline = true,
    },
  })

  popup:mount()
  render_lines()

  -- Focus the popup window
  vim.api.nvim_set_current_win(popup.winid)

  -- Keymaps using nui's map method
  local map_opts = { noremap = true, nowait = true }
  popup:map("n", "<Space>", toggle_selection, map_opts)
  popup:map("n", "<CR>", function() confirm_selection(callback) end, map_opts)
  popup:map("n", "q", close_picker, map_opts)
  popup:map("n", "<Esc>", close_picker, map_opts)
  popup:map("n", "n", select_none, map_opts)
end

return M
