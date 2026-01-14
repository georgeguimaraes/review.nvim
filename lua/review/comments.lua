local M = {}

local store = require("review.store")
local hooks = require("review.hooks")
local popup = require("review.popup")
local marks = require("review.marks")

local function notify(msg, level)
  vim.notify(msg, level, { title = "Review" })
end

---@param initial_type? "note"|"suggestion"|"issue"|"praise"
function M.add_at_cursor(initial_type)
  local file, line = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local existing = store.get_at_line(file, line)
  if existing then
    notify("Comment already exists at this line. Use edit instead.", vim.log.levels.WARN)
    return
  end

  popup.open(initial_type or "note", nil, function(comment_type, text)
    if comment_type and text then
      store.add(file, line, comment_type, text)
      marks.refresh()
      notify(string.format("Added %s comment", comment_type), vim.log.levels.INFO)
    end
  end)
end

-- Alias for backwards compatibility
function M.add_with_menu()
  M.add_at_cursor()
end

function M.edit_at_cursor()
  local file, line = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local comment = store.get_at_line(file, line)
  if not comment then
    notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  popup.open(comment.type, comment.text, function(new_type, text)
    if new_type and text then
      store.update(comment.id, text, new_type)
      marks.refresh()
      notify("Comment updated", vim.log.levels.INFO)
    end
  end)
end

function M.delete_at_cursor()
  local file, line = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local comment = store.get_at_line(file, line)
  if not comment then
    notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete this comment?",
  }, function(choice)
    if choice == "Yes" then
      store.delete(comment.id)
      marks.refresh()
      notify("Comment deleted", vim.log.levels.INFO)
    end
  end)
end

function M.goto_next()
  local file, line = hooks.get_cursor_position()
  if not file then
    return
  end

  local comments = store.get_for_file(file)
  for _, comment in ipairs(comments) do
    if comment.line > line then
      vim.api.nvim_win_set_cursor(0, { comment.line, 0 })
      return
    end
  end

  notify("No more comments in this file", vim.log.levels.INFO)
end

function M.goto_prev()
  local file, line = hooks.get_cursor_position()
  if not file then
    return
  end

  local comments = store.get_for_file(file)
  for i = #comments, 1, -1 do
    local comment = comments[i]
    if comment.line < line then
      vim.api.nvim_win_set_cursor(0, { comment.line, 0 })
      return
    end
  end

  notify("No previous comments in this file", vim.log.levels.INFO)
end

function M.list()
  local config = require("review.config").get()
  local all_comments = store.get_all()

  if #all_comments == 0 then
    notify("No comments yet", vim.log.levels.INFO)
    return
  end

  -- Build display items
  local items = {}
  for _, comment in ipairs(all_comments) do
    local type_info = config.comment_types[comment.type]
    local icon = type_info and type_info.icon or "●"
    local name = type_info and type_info.name or comment.type
    local display = string.format("%s %s:%d [%s] %s", icon, comment.file, comment.line, name, comment.text)
    table.insert(items, { display = display, comment = comment })
  end

  -- Show picker
  vim.ui.select(items, {
    prompt = "Comments:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    local comment = choice.comment

    -- Try to navigate to the file in codediff explorer
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if ok then
      local tabpage = hooks.get_current_tabpage()
      if tabpage then
        local explorer = lifecycle.get_explorer(tabpage)
        if explorer then
          local explorer_mod = require("codediff.ui.explorer")
          -- Find and select the file in explorer
          -- This is a best-effort navigation
          for i, node in ipairs(explorer.tree:get_nodes()) do
            if node.path == comment.file then
              explorer_mod.select_node(explorer, node)
              break
            end
          end
        end
      end
    end

    -- Jump to line after a short delay
    vim.defer_fn(function()
      pcall(vim.api.nvim_win_set_cursor, 0, { comment.line, 0 })
    end, 100)
  end)
end

return M
