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
---@type number|nil
local range_start = nil
---@type number|nil
local range_end = nil
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

local function is_in_range(idx)
  if not range_start or not range_end then
    return false
  end
  local lo = math.min(range_start, range_end)
  local hi = math.max(range_start, range_end)
  return idx >= lo and idx <= hi
end

local function format_line(idx, commit)
  local in_range = is_in_range(idx)
  local marker = in_range and "[x]" or "[ ]"
  local hash = commit.short_hash
  local meta = string.format("(%s, %s)", commit.author, commit.date)
  local line = string.format("%s %s %s %s", marker, hash, commit.message, meta)

  local marker_len = #marker
  local hash_start = marker_len + 1
  local hash_end = hash_start + #hash
  local meta_start = #line - #meta

  if #line > 120 then
    line = line:sub(1, 117) .. "..."
  end

  local line_len = #line
  local hl = {}

  if in_range then
    table.insert(hl, { "ReviewPickerSelected", 0, math.min(marker_len, line_len) })
  end
  if hash_start < line_len then
    table.insert(hl, { "ReviewPickerHash", hash_start, math.min(hash_end, line_len) })
  end
  if meta_start < line_len then
    table.insert(hl, { "ReviewPickerMeta", meta_start, line_len })
  end

  return line, hl
end

local function apply_line_hl(buf, row, highlights)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, ns_id, row, hl[2], {
      end_col = hl[3],
      hl_group = hl[1],
      priority = 200,
    })
  end
end

local function render_lines()
  if not popup then
    return
  end

  local buf = popup.bufnr
  local lines = {}
  local line_data = {}

  for i, commit in ipairs(commits) do
    local line, hl = format_line(i, commit)
    table.insert(lines, line)
    table.insert(line_data, { hl = hl })
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  ns_id = vim.api.nvim_create_namespace("review_picker")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for i, data in ipairs(line_data) do
    apply_line_hl(buf, i - 1, data.hl)
  end
end

local function toggle_range()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  if not commits[idx] then
    return
  end

  if not range_start then
    range_start = idx
    range_end = idx
  elseif idx == range_start and idx == range_end then
    range_start = nil
    range_end = nil
  else
    range_end = idx
  end
  render_lines()
end

local function select_none()
  range_start = nil
  range_end = nil
  render_lines()
end

local function close_picker()
  if popup then
    popup:unmount()
    popup = nil
  end
  commits = {}
  range_start = nil
  range_end = nil
end

local function confirm_selection(callback)
  local lo, hi

  if range_start and range_end then
    lo = math.min(range_start, range_end)
    hi = math.max(range_start, range_end)
  else
    local cursor = vim.api.nvim_win_get_cursor(0)
    local idx = cursor[1]
    if commits[idx] then
      lo = idx
      hi = idx
    end
  end

  if not lo or not hi then
    close_picker()
    callback(nil, nil)
    return
  end

  -- Git log returns newest first, so lower index = newer commit
  local newest = commits[lo]
  local oldest = commits[hi]

  close_picker()
  callback(oldest.hash .. "^", newest.hash)
end

function M.open(callback)
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR, { title = "review.nvim" })
    return
  end

  commits = fetch_commits(50)
  range_start = nil
  range_end = nil

  if #commits == 0 then
    vim.notify("No commits found", vim.log.levels.WARN, { title = "review.nvim" })
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
        bottom = " <Space> select | r reset | <CR> confirm | q quit ",
        bottom_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
    win_options = {
      cursorline = true,
      cursorlineopt = "line",
    },
  })

  popup:mount()
  render_lines()

  -- Focus the popup window and lock cursor to column 2 (middle of [ ])
  vim.api.nvim_set_current_win(popup.winid)
  vim.api.nvim_win_set_cursor(popup.winid, { 1, 1 })
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = popup.bufnr,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_win_set_cursor(0, { row, 1 })
    end,
  })

  -- Keymaps using nui's map method
  local map_opts = { noremap = true, nowait = true }
  popup:map("n", "<Space>", toggle_range, map_opts)
  popup:map("n", "<CR>", function() confirm_selection(callback) end, map_opts)
  popup:map("n", "q", close_picker, map_opts)
  popup:map("n", "<Esc>", close_picker, map_opts)
  popup:map("n", "r", select_none, map_opts)
end

return M
