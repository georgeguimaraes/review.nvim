local M = {}

local api = require("review.github.api")
local Popup = require("nui.popup")

---@type any
local submit_popup = nil

---Convert local comments to GitHub review threads format
---@param comments table[]
---@return { path: string, line: number, side: string, body: string }[]
local function convert_to_threads(comments)
  local threads = {}

  for _, comment in ipairs(comments) do
    local type_info = require("review.config").get().comment_types[comment.type]
    local prefix = type_info and string.format("[%s] ", string.upper(type_info.name)) or ""

    table.insert(threads, {
      path = comment.file,
      line = comment.line,
      side = "RIGHT", -- Comments on new changes (HEAD side of the diff)
      body = prefix .. comment.text,
    })
  end

  return threads
end

---Determine the suggested review event based on comment types
---@param comments table[]
---@return string
local function suggest_event(comments)
  local has_issue = false
  local has_praise = false

  for _, comment in ipairs(comments) do
    if comment.type == "issue" then
      has_issue = true
    elseif comment.type == "praise" then
      has_praise = true
    end
  end

  if has_issue then
    return "REQUEST_CHANGES"
  elseif has_praise and #comments == 1 then
    return "APPROVE"
  else
    return "COMMENT"
  end
end

---Show submit review UI
function M.show_submit_ui()
  local github = require("review.github")
  local pr = github.get_current_pr()

  if not pr then
    vim.notify("No active PR review", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local store = require("review.store")
  local comments = store.get_all()

  -- Get PR node ID for mutation
  local pr_node_id = api.get_pr_node_id(pr.number)
  if not pr_node_id then
    vim.notify("Failed to get PR ID", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local suggested = suggest_event(comments)

  -- Build preview
  local lines = {}
  table.insert(lines, string.format("PR #%d: %s", pr.number, pr.title))
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "")
  if #comments > 0 then
    table.insert(lines, string.format("Comments to submit: %d", #comments))
  else
    table.insert(lines, "No local comments (review body only)")
  end
  table.insert(lines, "")

  for _, comment in ipairs(comments) do
    local type_info = require("review.config").get().comment_types[comment.type]
    local icon = type_info and type_info.icon or "●"
    local preview = comment.text:gsub("\n", " ")
    if #preview > 40 then
      preview = preview:sub(1, 37) .. "..."
    end
    table.insert(lines, string.format("  %s %s:%d - %s", icon, comment.file, comment.line, preview))
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "")
  table.insert(lines, "Review type:")
  table.insert(lines, string.format("  [a] Approve%s", suggested == "APPROVE" and " (suggested)" or ""))
  table.insert(lines, string.format("  [c] Comment%s", suggested == "COMMENT" and " (suggested)" or ""))
  table.insert(lines, string.format("  [r] Request changes%s", suggested == "REQUEST_CHANGES" and " (suggested)" or ""))
  table.insert(lines, "")
  table.insert(lines, "  [q] Cancel")

  local width = 60
  local height = math.min(#lines + 2, vim.o.lines - 10)

  if submit_popup then
    submit_popup:unmount()
  end

  submit_popup = Popup({
    position = "50%",
    size = {
      width = width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = " Submit Review ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      buftype = "nofile",
    },
  })

  submit_popup:mount()

  -- Ensure popup has focus
  vim.api.nvim_set_current_win(submit_popup.winid)

  local buf = submit_popup.bufnr
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local map_opts = { noremap = true, nowait = true }

  local function close()
    submit_popup:unmount()
    submit_popup = nil
  end

  local function submit_with_event(event)
    close()
    M._prompt_body_and_submit(pr_node_id, pr.number, event, comments)
  end

  submit_popup:map("n", "a", function() submit_with_event("APPROVE") end, map_opts)
  submit_popup:map("n", "c", function() submit_with_event("COMMENT") end, map_opts)
  submit_popup:map("n", "r", function() submit_with_event("REQUEST_CHANGES") end, map_opts)
  submit_popup:map("n", "q", close, map_opts)
  submit_popup:map("n", "<Esc>", close, map_opts)
end

---Prompt for review body and submit
---@param pr_node_id string
---@param pr_number number
---@param event string
---@param comments table[]
function M._prompt_body_and_submit(pr_node_id, pr_number, event, comments)
  local event_names = {
    APPROVE = "Approve",
    COMMENT = "Comment",
    REQUEST_CHANGES = "Request changes",
  }

  vim.ui.input({
    prompt = string.format("Review summary (%s): ", event_names[event] or event),
  }, function(body)
    if body == nil then
      -- Cancelled
      return
    end

    M._do_submit(pr_node_id, pr_number, event, body, comments)
  end)
end

---Actually submit the review
---@param pr_node_id string
---@param pr_number number
---@param event string
---@param body string
---@param comments table[]
function M._do_submit(pr_node_id, pr_number, event, body, comments)
  vim.notify("Submitting review...", vim.log.levels.INFO, { title = "Review" })

  local threads = convert_to_threads(comments)

  local ok, err = api.submit_review(pr_node_id, event, body, threads)

  if not ok then
    vim.notify("Failed to submit review: " .. (err or "unknown error"), vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local event_names = {
    APPROVE = "approved",
    COMMENT = "commented on",
    REQUEST_CHANGES = "requested changes on",
  }

  local msg
  if #comments > 0 then
    msg = string.format("Successfully %s PR #%d with %d comment(s)", event_names[event] or "reviewed", pr_number, #comments)
  else
    msg = string.format("Successfully %s PR #%d", event_names[event] or "reviewed", pr_number)
  end
  vim.notify(msg, vim.log.levels.INFO, { title = "Review" })

  -- Ask to clear local comments if there were any
  if #comments > 0 then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Clear local comments?",
    }, function(choice)
      if choice == "Yes" then
        local store = require("review.store")
        store.clear()
        require("review.marks").clear_all()
        vim.notify("Local comments cleared", vim.log.levels.INFO, { title = "Review" })
      end
    end)
  end
end

---Quick submit with suggested event (no UI)
function M.quick_submit()
  local github = require("review.github")
  local pr = github.get_current_pr()

  if not pr then
    vim.notify("No active PR review", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local store = require("review.store")
  local comments = store.get_all()

  local pr_node_id = api.get_pr_node_id(pr.number)
  if not pr_node_id then
    vim.notify("Failed to get PR ID", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  local event = suggest_event(comments)
  M._prompt_body_and_submit(pr_node_id, pr.number, event, comments)
end

return M
