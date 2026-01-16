local M = {}

local api = require("review.github.api")
local Popup = require("nui.popup")

local ns_id = vim.api.nvim_create_namespace("review_github")
local hover_ns_id = vim.api.nvim_create_namespace("review_github_hover")

-- Track current hover state
local current_hover = {
  bufnr = nil,
  line = nil,
}

---@class GitHubThread
---@field id string Thread ID
---@field path string File path
---@field line number Line number
---@field start_line number|nil Start line for multi-line comments
---@field side "LEFT"|"RIGHT" Which side of diff
---@field is_resolved boolean
---@field is_outdated boolean
---@field comments GitHubComment[]

---@class GitHubComment
---@field id string Comment ID
---@field author string
---@field body string
---@field created_at string
---@field reactions table<string, number>

---@type GitHubThread[]
M.threads = {}

---@type table<string, GitHubThread[]> threads by file path
M.threads_by_file = {}

---@type any Current popup
local thread_popup = nil

---Fetch threads for a PR and store them
---@param pr_number number
---@return boolean success
function M.fetch(pr_number)
  local threads = api.get_review_threads(pr_number)
  if not threads then
    return false
  end

  M.threads = threads
  M.threads_by_file = {}

  for _, thread in ipairs(threads) do
    if not M.threads_by_file[thread.path] then
      M.threads_by_file[thread.path] = {}
    end
    table.insert(M.threads_by_file[thread.path], thread)
  end

  return true
end

---Clear stored threads
function M.clear()
  M.threads = {}
  M.threads_by_file = {}
end

---Get threads for a specific file
---@param file string
---@return GitHubThread[]
function M.get_for_file(file)
  return M.threads_by_file[file] or {}
end

---Get thread at a specific line
---@param file string
---@param line number
---@return GitHubThread|nil
function M.get_at_line(file, line)
  local threads = M.threads_by_file[file] or {}
  for _, thread in ipairs(threads) do
    if thread.line == line then
      return thread
    end
  end
  return nil
end

---Normalize path for matching
---@param path string
---@return string
local function normalize_path(path)
  if not path then
    return path
  end
  path = path:gsub("^%./", "")
  path = path:gsub("/+$", "")
  return path
end

---Format relative time
---@param iso_time string
---@return string
local function format_relative_time(iso_time)
  -- Simple relative time formatting
  local year, month, day, hour, min, sec = iso_time:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return iso_time
  end

  local then_time = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  local diff = os.time() - then_time
  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins == 1 and "1 minute ago" or mins .. " minutes ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours == 1 and "1 hour ago" or hours .. " hours ago"
  elseif diff < 604800 then
    local days = math.floor(diff / 86400)
    return days == 1 and "1 day ago" or days .. " days ago"
  else
    local weeks = math.floor(diff / 604800)
    return weeks == 1 and "1 week ago" or weeks .. " weeks ago"
  end
end

---Get file path for a buffer using lifecycle API (consistent with hooks.get_cursor_position)
---@param bufnr number
---@return string|nil
local function get_file_for_buffer(bufnr)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  local sess = lifecycle.get_session(tabpage)
  if not sess then
    return nil
  end

  local orig_path, mod_path = lifecycle.get_paths(tabpage)
  local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)

  -- Determine which file based on buffer
  local file_path
  if bufnr == orig_buf then
    file_path = orig_path
  elseif bufnr == mod_buf then
    file_path = mod_path
  end

  if not file_path then
    return nil
  end

  -- Get relative path using git context
  local git_ctx = lifecycle.get_git_context(tabpage)
  if git_ctx and git_ctx.git_root then
    local abs_path = vim.fn.fnamemodify(file_path, ":p")
    local rel_path = abs_path:gsub("^" .. vim.pesc(git_ctx.git_root) .. "/", "")
    return normalize_path(rel_path)
  end

  return normalize_path(vim.fn.fnamemodify(file_path, ":."))
end

---Render GitHub threads for a buffer
---@param bufnr number
function M.render_for_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Try to get file path from lifecycle API first (consistent with hooks.get_cursor_position)
  local file = get_file_for_buffer(bufnr)

  -- Fallback to buffer name parsing if lifecycle API fails
  if not file then
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if not bufname or bufname == "" then
      return
    end

    -- Extract file path
    if bufname:match("^codediff://") then
      local path = bufname:match("^codediff://[^/]+/(.+)%?") or bufname:match("^codediff://[^/]+/(.+)$")
      if path then
        file = normalize_path(path)
      end
    else
      file = normalize_path(vim.fn.fnamemodify(bufname, ":."))
    end
  end

  if not file then
    return
  end

  local threads = M.get_for_file(file)

  -- Clear previous GitHub thread marks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  for _, thread in ipairs(threads) do
    local line = thread.line - 1
    if line >= 0 then
      local icon = thread.is_resolved and "✓" or "◆"
      local hl = thread.is_resolved and "ReviewGitHubResolved" or "ReviewGitHubThread"
      local line_hl = thread.is_outdated and "ReviewGitHubOutdated" or nil

      -- Just show gutter sign - thread details shown on hover
      local reply_count = thread.comments and #thread.comments or 0
      local virt_text = nil
      if reply_count > 1 then
        virt_text = { { string.format(" 💬 %d", reply_count), "ReviewGitHubVirtText" } }
      elseif reply_count == 1 then
        virt_text = { { " 💬", "ReviewGitHubVirtText" } }
      end

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line, 0, {
        sign_text = icon,
        sign_hl_group = hl,
        line_hl_group = line_hl,
        virt_text = virt_text,
        virt_text_pos = "eol",
      })
    end
  end
end

---Show thread details on hover (called on CursorHold)
---@param bufnr number
---@param line number 1-indexed line number
function M.show_hover(bufnr, line)
  -- Clear previous hover
  M.clear_hover()

  local file = get_file_for_buffer(bufnr)
  if not file then
    return
  end

  local thread = M.get_at_line(file, line)
  if not thread or not thread.comments or #thread.comments == 0 then
    return
  end

  current_hover.bufnr = bufnr
  current_hover.line = line

  local first = thread.comments[1]
  local author = first.author or "unknown"
  local time_ago = format_relative_time(first.created_at)
  local icon = thread.is_resolved and "✓" or "◆"
  local hl = thread.is_resolved and "ReviewGitHubResolved" or "ReviewGitHubThread"

  -- Build virtual lines for hover display
  local virt_lines = {}

  -- Get first comment body lines (limit to 5 lines)
  local body_lines = vim.split(first.body, "\n")
  local display_lines = {}
  for i = 1, math.min(5, #body_lines) do
    local l = body_lines[i]
    if #l > 60 then
      l = l:sub(1, 57) .. "..."
    end
    table.insert(display_lines, l)
  end
  if #body_lines > 5 then
    table.insert(display_lines, "...")
  end

  -- Calculate box width
  local header_text = string.format("%s @%s • %s", icon, author, time_ago)
  local max_width = vim.fn.strdisplaywidth(header_text)
  for _, l in ipairs(display_lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(l))
  end
  local reply_text = ""
  if #thread.comments > 1 then
    reply_text = string.format("💬 %d replies (Enter to view)", #thread.comments - 1)
    max_width = math.max(max_width, vim.fn.strdisplaywidth(reply_text))
  end
  local content_width = math.max(max_width, 20)

  -- Top border
  local header_padding = content_width - vim.fn.strdisplaywidth(header_text) + 1
  local top_line = "╭─" .. header_text .. string.rep("─", math.max(0, header_padding)) .. "╮"
  table.insert(virt_lines, { { top_line, hl } })

  -- Body lines
  for _, body_line in ipairs(display_lines) do
    local text_width = vim.fn.strdisplaywidth(body_line)
    local padding = content_width - text_width
    local content = "│ " .. body_line .. string.rep(" ", padding) .. " │"
    table.insert(virt_lines, { { content, hl } })
  end

  -- Reply count
  if reply_text ~= "" then
    local reply_width = vim.fn.strdisplaywidth(reply_text)
    local reply_padding = content_width - reply_width
    local reply_line = "│ " .. reply_text .. string.rep(" ", reply_padding) .. " │"
    table.insert(virt_lines, { { reply_line, "ReviewGitHubVirtText" } })
  end

  -- Hint line
  local hint_text = "Enter: view • r: reply • R: resolve"
  local hint_width = vim.fn.strdisplaywidth(hint_text)
  local hint_padding = content_width - hint_width
  if hint_padding >= 0 then
    local hint_line = "│ " .. hint_text .. string.rep(" ", hint_padding) .. " │"
    table.insert(virt_lines, { { hint_line, "Comment" } })
  end

  -- Bottom border
  local bottom = "╰" .. string.rep("─", content_width + 2) .. "╯"
  table.insert(virt_lines, { { bottom, hl } })

  -- Show as virtual lines below the current line
  pcall(vim.api.nvim_buf_set_extmark, bufnr, hover_ns_id, line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })
end

---Clear hover display
function M.clear_hover()
  if current_hover.bufnr and vim.api.nvim_buf_is_valid(current_hover.bufnr) then
    vim.api.nvim_buf_clear_namespace(current_hover.bufnr, hover_ns_id, 0, -1)
  end
  current_hover.bufnr = nil
  current_hover.line = nil
end

---Setup hover autocmds for a buffer
---@param bufnr number
function M.setup_hover(bufnr)
  local group = vim.api.nvim_create_augroup("ReviewGitHubHover" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    buffer = bufnr,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      M.show_hover(bufnr, cursor[1])
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      -- Clear hover when cursor moves to a different line
      local cursor = vim.api.nvim_win_get_cursor(0)
      if current_hover.line and cursor[1] ~= current_hover.line then
        M.clear_hover()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      M.clear_hover()
    end,
  })
end

---Format reactions for display
---@param reactions table<string, number>
---@return string
local function format_reactions(reactions)
  if not reactions or vim.tbl_isempty(reactions) then
    return ""
  end

  local emoji_map = {
    THUMBS_UP = "👍",
    THUMBS_DOWN = "👎",
    LAUGH = "😄",
    HOORAY = "🎉",
    CONFUSED = "😕",
    HEART = "❤️",
    ROCKET = "🚀",
    EYES = "👀",
  }

  local parts = {}
  for reaction, count in pairs(reactions) do
    local emoji = emoji_map[reaction] or reaction
    table.insert(parts, emoji .. " " .. count)
  end

  return table.concat(parts, "  ")
end

---Show thread popup at cursor
function M.show_thread_at_cursor()
  local hooks = require("review.hooks")
  local file, line = hooks.get_cursor_position()

  if not file or not line then
    vim.notify("Could not determine cursor position", vim.log.levels.WARN, { title = "Review" })
    return
  end

  local thread = M.get_at_line(file, line)
  if not thread then
    vim.notify("No GitHub thread at this line", vim.log.levels.INFO, { title = "Review" })
    return
  end

  M.show_thread(thread)
end

---Show a thread in a popup
---@param thread GitHubThread
function M.show_thread(thread)
  if thread_popup then
    thread_popup:unmount()
    thread_popup = nil
  end

  local lines = {}
  local highlights = {}

  -- Header
  local status = thread.is_resolved and "✓ Resolved" or "◆ Open"
  if thread.is_outdated then
    status = status .. " (outdated)"
  end
  table.insert(lines, status)
  table.insert(highlights, { line = #lines, hl = thread.is_resolved and "ReviewGitHubResolved" or "ReviewGitHubThread" })
  table.insert(lines, string.rep("─", 50))

  -- Comments
  for i, comment in ipairs(thread.comments) do
    if i > 1 then
      table.insert(lines, "")
      table.insert(lines, string.rep("─", 50))
    end

    -- Author and time
    local author_line = string.format("@%s (%s)", comment.author, format_relative_time(comment.created_at))
    table.insert(lines, author_line)
    table.insert(highlights, { line = #lines, hl = "ReviewGitHubAuthor" })

    -- Body
    for _, body_line in ipairs(vim.split(comment.body, "\n")) do
      table.insert(lines, body_line)
    end

    -- Reactions
    local reactions_str = format_reactions(comment.reactions)
    if reactions_str ~= "" then
      table.insert(lines, "")
      table.insert(lines, reactions_str)
    end
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "[r]eply  [R]esolve  [e]dit  [d]elete  [+]react  [o]pen  [q]uit")
  table.insert(highlights, { line = #lines, hl = "Comment" })

  -- Calculate popup size
  local max_width = 60
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line) + 4)
  end
  max_width = math.min(max_width, vim.o.columns - 10)
  local height = math.min(#lines, vim.o.lines - 10)

  thread_popup = Popup({
    position = "50%",
    size = {
      width = max_width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = " GitHub Thread ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
    win_options = {
      wrap = true,
    },
  })

  thread_popup:mount()

  -- Ensure popup has focus
  vim.api.nvim_set_current_win(thread_popup.winid)

  local buf = thread_popup.bufnr
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  local hl_ns = vim.api.nvim_create_namespace("review_thread_popup")
  for _, hl_info in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, hl_ns, hl_info.hl, hl_info.line - 1, 0, -1)
  end

  -- Keymaps
  local map_opts = { noremap = true, nowait = true }

  thread_popup:map("n", "q", function()
    thread_popup:unmount()
    thread_popup = nil
  end, map_opts)

  thread_popup:map("n", "<Esc>", function()
    thread_popup:unmount()
    thread_popup = nil
  end, map_opts)

  thread_popup:map("n", "r", function()
    thread_popup:unmount()
    thread_popup = nil
    M.reply_to_thread(thread)
  end, map_opts)

  thread_popup:map("n", "R", function()
    thread_popup:unmount()
    thread_popup = nil
    M.toggle_resolve(thread)
  end, map_opts)

  thread_popup:map("n", "e", function()
    thread_popup:unmount()
    thread_popup = nil
    M.edit_comment(thread)
  end, map_opts)

  thread_popup:map("n", "d", function()
    thread_popup:unmount()
    thread_popup = nil
    M.delete_comment(thread)
  end, map_opts)

  thread_popup:map("n", "+", function()
    thread_popup:unmount()
    thread_popup = nil
    M.add_reaction(thread)
  end, map_opts)

  thread_popup:map("n", "o", function()
    thread_popup:unmount()
    thread_popup = nil
    M.open_thread_in_browser()
  end, map_opts)
end

---Reply to a thread
---@param thread GitHubThread
function M.reply_to_thread(thread)
  vim.ui.input({ prompt = "Reply: " }, function(input)
    if not input or input == "" then
      return
    end

    local github = require("review.github")
    local pr = github.get_current_pr()
    if not pr then
      vim.notify("No active PR", vim.log.levels.ERROR, { title = "Review" })
      return
    end

    -- Use GraphQL to reply
    local mutation = [[
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {
    comment {
      id
    }
  }
}
]]

    local variables = vim.json.encode({
      threadId = thread.id,
      body = input,
    })

    local cmd = string.format(
      "gh api graphql -f query=%s -f variables=%s",
      vim.fn.shellescape(mutation),
      vim.fn.shellescape(variables)
    )

    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to post reply: " .. vim.trim(result), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Reply posted", vim.log.levels.INFO, { title = "Review" })

    -- Refresh threads
    M.fetch(pr.number)
    M.render_all()
  end)
end

---Toggle thread resolved status
---@param thread GitHubThread
function M.toggle_resolve(thread)
  local github = require("review.github")
  local pr = github.get_current_pr()
  if not pr then
    vim.notify("No active PR", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local mutation
  if thread.is_resolved then
    mutation = [[
mutation($threadId: ID!) {
  unresolveReviewThread(input: { threadId: $threadId }) {
    thread { id }
  }
}
]]
  else
    mutation = [[
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id }
  }
}
]]
  end

  local variables = vim.json.encode({ threadId = thread.id })
  local cmd = string.format(
    "gh api graphql -f query=%s -f variables=%s",
    vim.fn.shellescape(mutation),
    vim.fn.shellescape(variables)
  )

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to update thread: " .. vim.trim(result), vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local action = thread.is_resolved and "Unresolved" or "Resolved"
  vim.notify("Thread " .. action:lower(), vim.log.levels.INFO, { title = "Review" })

  -- Refresh threads
  M.fetch(pr.number)
  M.render_all()
end

---Render threads for all codediff buffers
function M.render_all()
  local ok, hooks = pcall(require, "review.hooks")
  if not ok then
    return
  end

  local orig_buf, mod_buf = hooks.get_buffers()
  if orig_buf then
    M.render_for_buffer(orig_buf)
    M.setup_hover(orig_buf)
  end
  if mod_buf then
    M.render_for_buffer(mod_buf)
    M.setup_hover(mod_buf)
  end
end

---Navigate to next thread
function M.next_thread()
  local hooks = require("review.hooks")
  local file, current_line = hooks.get_cursor_position()
  if not file then
    return
  end

  local threads = M.get_for_file(file)
  table.sort(threads, function(a, b) return a.line < b.line end)

  for _, thread in ipairs(threads) do
    if thread.line > current_line then
      vim.api.nvim_win_set_cursor(0, { thread.line, 0 })
      return
    end
  end

  -- Wrap to first
  if #threads > 0 then
    vim.api.nvim_win_set_cursor(0, { threads[1].line, 0 })
  end
end

---Navigate to previous thread
function M.prev_thread()
  local hooks = require("review.hooks")
  local file, current_line = hooks.get_cursor_position()
  if not file then
    return
  end

  local threads = M.get_for_file(file)
  table.sort(threads, function(a, b) return a.line > b.line end)

  for _, thread in ipairs(threads) do
    if thread.line < current_line then
      vim.api.nvim_win_set_cursor(0, { thread.line, 0 })
      return
    end
  end

  -- Wrap to last
  if #threads > 0 then
    vim.api.nvim_win_set_cursor(0, { threads[#threads].line, 0 })
  end
end

---Get the current line content from buffer
---@return string|nil
local function get_current_line_content()
  local current_buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(current_buf, line_num - 1, line_num, false)
  return lines[1]
end

---Start a new thread at cursor position
---@param default_type? "note"|"suggestion" Default type (default: "note")
function M.start_new_thread(default_type)
  local hooks = require("review.hooks")
  local popup = require("review.popup")
  local file, line = hooks.get_cursor_position()

  if not file or not line then
    vim.notify("Could not determine cursor position", vim.log.levels.WARN, { title = "Review" })
    return
  end

  -- Validate file path is not empty
  if file == "" then
    vim.notify("Empty file path detected", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local github = require("review.github")
  local pr = github.get_current_pr()
  if not pr then
    vim.notify("No active PR review", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local pr_node_id = api.get_pr_node_id(pr.number)
  if not pr_node_id or pr_node_id == "" then
    vim.notify("Failed to get PR ID", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  -- Get current line for suggestion pre-fill
  local current_content = get_current_line_content() or ""

  -- Pre-fill for suggestions
  local initial_text = nil
  if default_type == "suggestion" then
    initial_text = "```suggestion\n" .. current_content .. "\n```"
  end

  -- Only Note and Suggestion for GitHub threads
  local allowed_types = { "note", "suggestion" }

  popup.open(default_type or "note", initial_text, function(comment_type, text)
    if not comment_type or not text or text == "" then
      return
    end

    local ok, err = api.add_review_thread(pr_node_id, file, line, text)
    if not ok then
      vim.notify("Failed to create thread: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Thread created", vim.log.levels.INFO, { title = "Review" })

    -- Optimistically add thread locally for immediate display
    local new_thread = {
      id = "pending_" .. os.time(),
      path = file,
      line = line,
      start_line = nil,
      side = "RIGHT",
      is_resolved = false,
      is_outdated = false,
      comments = {
        {
          id = "pending_comment_" .. os.time(),
          author = api.get_current_user() or "you",
          body = text,
          created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          reactions = {},
        },
      },
    }

    table.insert(M.threads, new_thread)
    if not M.threads_by_file[file] then
      M.threads_by_file[file] = {}
    end
    table.insert(M.threads_by_file[file], new_thread)

    -- Render immediately
    vim.schedule(function()
      M.render_all()
    end)

    -- Then refresh from GitHub in background to get real IDs
    vim.defer_fn(function()
      M.fetch(pr.number)
      M.render_all()
    end, 1000)
  end, current_content, allowed_types)
end

---Start a new suggestion thread at cursor position
---Uses GitHub's suggestion syntax for one-click apply
function M.start_suggestion_thread()
  M.start_new_thread("suggestion")
end

---Get lines content from buffer for a range
---@param start_line number
---@param end_line number
---@return string[]
local function get_lines_content(start_line, end_line)
  local current_buf = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_lines(current_buf, start_line - 1, end_line, false)
end

---Start a multi-line thread (visual selection)
---@param default_type? "note"|"suggestion" Default type (default: "note")
function M.start_multiline_thread(default_type)
  local hooks = require("review.hooks")
  local popup = require("review.popup")
  local file = hooks.get_cursor_position()

  if not file then
    vim.notify("Could not determine cursor position", vim.log.levels.WARN, { title = "Review" })
    return
  end

  -- Get visual selection range
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local github = require("review.github")
  local pr = github.get_current_pr()
  if not pr then
    vim.notify("No active PR review", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local pr_node_id = api.get_pr_node_id(pr.number)
  if not pr_node_id then
    vim.notify("Failed to get PR ID", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  -- Get selected lines for suggestion pre-fill
  local selected_lines = get_lines_content(start_line, end_line)
  local selected_content = table.concat(selected_lines, "\n")

  -- Pre-fill for suggestions
  local initial_text = nil
  if default_type == "suggestion" then
    initial_text = "```suggestion\n" .. selected_content .. "\n```"
  end

  -- Only Note and Suggestion for GitHub threads
  local allowed_types = { "note", "suggestion" }

  popup.open(default_type or "note", initial_text, function(comment_type, text)
    if not comment_type or not text or text == "" then
      return
    end

    local ok, err = api.add_review_thread(pr_node_id, file, end_line, text, start_line)
    if not ok then
      vim.notify("Failed to create thread: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Multi-line thread created", vim.log.levels.INFO, { title = "Review" })

    -- Optimistically add thread locally for immediate display
    local new_thread = {
      id = "pending_" .. os.time(),
      path = file,
      line = end_line,
      start_line = start_line,
      side = "RIGHT",
      is_resolved = false,
      is_outdated = false,
      comments = {
        {
          id = "pending_comment_" .. os.time(),
          author = api.get_current_user() or "you",
          body = text,
          created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          reactions = {},
        },
      },
    }

    table.insert(M.threads, new_thread)
    if not M.threads_by_file[file] then
      M.threads_by_file[file] = {}
    end
    table.insert(M.threads_by_file[file], new_thread)

    -- Render immediately
    vim.schedule(function()
      M.render_all()
    end)

    -- Then refresh from GitHub in background to get real IDs
    vim.defer_fn(function()
      M.fetch(pr.number)
      M.render_all()
    end, 1000)
  end, selected_content, allowed_types)
end

---Start a multi-line suggestion (visual selection)
function M.start_multiline_suggestion()
  M.start_multiline_thread("suggestion")
end

---Edit a comment in a thread (edits the last comment you authored)
---@param thread GitHubThread
function M.edit_comment(thread)
  local current_user = api.get_current_user()
  if not current_user then
    vim.notify("Could not determine current user", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  -- Find last comment by current user
  local my_comment = nil
  for i = #thread.comments, 1, -1 do
    if thread.comments[i].author == current_user then
      my_comment = thread.comments[i]
      break
    end
  end

  if not my_comment then
    vim.notify("No comment to edit (you haven't commented)", vim.log.levels.WARN, { title = "Review" })
    return
  end

  vim.ui.input({
    prompt = "Edit comment: ",
    default = my_comment.body,
  }, function(new_body)
    if new_body == nil or new_body == "" then
      return
    end

    local github = require("review.github")
    local pr = github.get_current_pr()
    if not pr then
      return
    end

    local ok, err = api.update_comment(my_comment.id, new_body)
    if not ok then
      vim.notify("Failed to edit comment: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Comment updated", vim.log.levels.INFO, { title = "Review" })

    M.fetch(pr.number)
    M.render_all()
  end)
end

---Delete a comment in a thread (deletes the last comment you authored)
---@param thread GitHubThread
function M.delete_comment(thread)
  local current_user = api.get_current_user()
  if not current_user then
    vim.notify("Could not determine current user", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  -- Find last comment by current user
  local my_comment = nil
  for i = #thread.comments, 1, -1 do
    if thread.comments[i].author == current_user then
      my_comment = thread.comments[i]
      break
    end
  end

  if not my_comment then
    vim.notify("No comment to delete (you haven't commented)", vim.log.levels.WARN, { title = "Review" })
    return
  end

  vim.ui.select({ "Yes", "No" }, { prompt = "Delete your comment?" }, function(choice)
    if choice ~= "Yes" then
      return
    end

    local github = require("review.github")
    local pr = github.get_current_pr()
    if not pr then
      return
    end

    local ok, err = api.delete_comment(my_comment.id)
    if not ok then
      vim.notify("Failed to delete comment: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Comment deleted", vim.log.levels.INFO, { title = "Review" })

    M.fetch(pr.number)
    M.render_all()
  end)
end

---Add reaction to last comment in thread
---@param thread GitHubThread
function M.add_reaction(thread)
  if not thread.comments or #thread.comments == 0 then
    vim.notify("No comments to react to", vim.log.levels.WARN, { title = "Review" })
    return
  end

  local reactions = {
    { label = "👍 Thumbs up", value = "THUMBS_UP" },
    { label = "👎 Thumbs down", value = "THUMBS_DOWN" },
    { label = "😄 Laugh", value = "LAUGH" },
    { label = "🎉 Hooray", value = "HOORAY" },
    { label = "😕 Confused", value = "CONFUSED" },
    { label = "❤️ Heart", value = "HEART" },
    { label = "🚀 Rocket", value = "ROCKET" },
    { label = "👀 Eyes", value = "EYES" },
  }

  local labels = {}
  for _, r in ipairs(reactions) do
    table.insert(labels, r.label)
  end

  vim.ui.select(labels, { prompt = "Add reaction:" }, function(choice, idx)
    if not choice or not idx then
      return
    end

    local github = require("review.github")
    local pr = github.get_current_pr()
    if not pr then
      return
    end

    local last_comment = thread.comments[#thread.comments]
    local ok, err = api.add_reaction(last_comment.id, reactions[idx].value)
    if not ok then
      vim.notify("Failed to add reaction: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
      return
    end

    vim.notify("Reaction added", vim.log.levels.INFO, { title = "Review" })

    M.fetch(pr.number)
    M.render_all()
  end)
end

---Open thread in browser
function M.open_thread_in_browser()
  local hooks = require("review.hooks")
  local file, line = hooks.get_cursor_position()

  if not file or not line then
    return false
  end

  local thread = M.get_at_line(file, line)
  if not thread then
    return false
  end

  local github = require("review.github")
  local pr = github.get_current_pr()
  if not pr then
    return false
  end

  -- GitHub PR file URL with anchor to the file
  -- Format: https://github.com/owner/repo/pull/number/files#diff-<hash>
  -- For simplicity, open the files changed page
  local url = string.format("%s/files", pr.url)
  vim.fn.system(string.format("open %s", vim.fn.shellescape(url)))
  vim.notify("Opened PR files in browser", vim.log.levels.INFO, { title = "Review" })
  return true
end

---Show PR description popup
function M.show_pr_description()
  local github = require("review.github")
  local pr = github.get_current_pr()
  if not pr then
    vim.notify("No active PR review", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local lines = {}
  local highlights = {}

  -- Title
  table.insert(lines, string.format("#%d %s", pr.number, pr.title))
  table.insert(highlights, { line = 1, hl = "Title" })

  -- Meta
  table.insert(lines, "")
  table.insert(lines, string.format("Author: @%s", pr.author))
  table.insert(lines, string.format("Branch: %s → %s", pr.head_ref, pr.base_ref))
  if pr.additions and pr.deletions then
    table.insert(lines, string.format("Changes: +%d -%d (%d files)", pr.additions, pr.deletions, pr.changed_files or 0))
  end
  table.insert(lines, string.format("URL: %s", pr.url))

  -- Body
  table.insert(lines, "")
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  if pr.body and pr.body ~= "" then
    for _, line in ipairs(vim.split(pr.body, "\n")) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "(no description)")
    table.insert(highlights, { line = #lines, hl = "Comment" })
  end

  -- Calculate size
  local max_width = 70
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line) + 4)
  end
  max_width = math.min(max_width, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  local popup = Popup({
    position = "50%",
    size = {
      width = max_width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = " PR Description ",
        top_align = "center",
        bottom = " q: close • o: open in browser ",
        bottom_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
    win_options = {
      wrap = true,
    },
  })

  popup:mount()

  -- Ensure popup has focus
  vim.api.nvim_set_current_win(popup.winid)

  local buf = popup.bufnr
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Apply highlights
  local hl_ns = vim.api.nvim_create_namespace("review_pr_desc")
  for _, hl_info in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, hl_ns, hl_info.hl, hl_info.line - 1, 0, -1)
  end

  local map_opts = { noremap = true, nowait = true }
  popup:map("n", "q", function() popup:unmount() end, map_opts)
  popup:map("n", "<Esc>", function() popup:unmount() end, map_opts)
  popup:map("n", "o", function()
    popup:unmount()
    vim.fn.system(string.format("open %s", vim.fn.shellescape(pr.url)))
    vim.notify("Opened PR in browser", vim.log.levels.INFO, { title = "Review" })
  end, map_opts)
end

return M
