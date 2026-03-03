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
  local is_selected = selected[commit.hash] and true or false
  local marker = is_selected and "[x]" or "[ ]"
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

  if is_selected then
    table.insert(hl, { "ReviewPickerSelected", 0, math.min(marker_len, line_len) })
  end
  if hash_start < line_len then
    table.insert(hl, { "ReviewPickerHash", hash_start, math.min(hash_end, line_len) })
  end
  if meta_start < line_len then
    table.insert(hl, { "ReviewPickerMeta", meta_start, line_len })
  end

  return line, hl, is_selected
end

local function apply_line_hl(buf, row, line_len, highlights, is_selected)
  if is_selected then
    vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
      end_col = line_len,
      hl_group = "Visual",
      hl_eol = true,
      priority = 100,
    })
  end
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

  for _, commit in ipairs(commits) do
    local line, hl, is_sel = format_line(commit)
    table.insert(lines, line)
    table.insert(line_data, { hl = hl, is_selected = is_sel, len = #line })
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  ns_id = vim.api.nvim_create_namespace("review_picker")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for i, data in ipairs(line_data) do
    apply_line_hl(buf, i - 1, data.len, data.hl, data.is_selected)
  end
end

local function update_line(line_num)
  if not popup then return end
  local buf = popup.bufnr
  local commit = commits[line_num]
  if not commit then return end

  local line, hl, is_sel = format_line(commit)

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, line_num - 1, line_num, false, { line })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  if ns_id then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, line_num - 1, line_num)
    apply_line_hl(buf, line_num - 1, #line, hl, is_sel)
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

  -- If nothing explicitly selected, use the commit under the cursor
  if #selected_commits == 0 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local commit = commits[cursor[1]]
    if commit then
      selected_commits = { commit }
    end
  end

  close_picker()

  if #selected_commits == 0 then
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
        bottom = " <Space> select range | <CR> confirm | q quit | n clear ",
        bottom_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
    win_options = {
      cursorline = true,
      cursorlineopt = "both",
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
