local M = {}

local config = require("review.config")

---@param initial_type? "note"|"suggestion"|"issue"|"praise"
---@param initial_text? string
---@param callback fun(comment_type: string|nil, text: string|nil)
---@param current_line? string Current line content for suggestion pre-fill
---@param allowed_types? string[] Types to show (default: all types)
function M.open(initial_type, initial_text, callback, current_line, allowed_types)
  local ok_popup, Popup = pcall(require, "nui.popup")
  local ok_layout, Layout = pcall(require, "nui.layout")

  if not (ok_popup and ok_layout) then
    vim.notify("nui.nvim is required for comment input", vim.log.levels.ERROR, { title = "Review" })
    callback(nil, nil)
    return
  end

  -- Save current window to restore focus later
  local prev_win = vim.api.nvim_get_current_win()

  local function restore_focus()
    vim.defer_fn(function()
      if prev_win and vim.api.nvim_win_is_valid(prev_win) then
        vim.api.nvim_set_current_win(prev_win)
      end
    end, 10)
  end

  local cfg = config.get()
  local type_keys = allowed_types or { "note", "suggestion", "issue", "praise" }
  local current_type_idx = 1

  -- Find initial type index
  if initial_type then
    for i, key in ipairs(type_keys) do
      if key == initial_type then
        current_type_idx = i
        break
      end
    end
  end

  -- Type selector popup (top)
  local type_popup = Popup({
    border = {
      style = "rounded",
      text = {
        top = " Type (TAB to switch) ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  -- Text input popup (bottom) - using Popup for multi-line support
  local text_popup = Popup({
    border = {
      style = "rounded",
      text = {
        top = " Comment ",
        top_align = "center",
        bottom = " C-s: submit • Esc: cancel ",
        bottom_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
  })

  local layout = Layout(
    {
      position = "50%",
      size = {
        width = 60,
        height = 10,
      },
    },
    Layout.Box({
      Layout.Box(type_popup, { size = 3 }),
      Layout.Box(text_popup, { size = 7 }),
    }, { dir = "col" })
  )

  local function get_text()
    local lines = vim.api.nvim_buf_get_lines(text_popup.bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")
    -- Trim trailing whitespace/newlines
    text = text:gsub("%s+$", "")
    return text
  end

  local function render_types()
    local parts = {}
    for i, key in ipairs(type_keys) do
      local info = cfg.comment_types[key]
      local icon = info and info.icon or ""
      local name = info and info.name or key
      if i == current_type_idx then
        table.insert(parts, string.format("[%s %s]", icon, name))
      else
        table.insert(parts, string.format(" %s %s ", icon, name))
      end
    end
    local line = table.concat(parts, " ")
    vim.api.nvim_buf_set_lines(type_popup.bufnr, 0, -1, false, { line })
    vim.api.nvim_set_option_value("modifiable", false, { buf = type_popup.bufnr })
  end

  local function cycle_type()
    current_type_idx = current_type_idx % #type_keys + 1
    vim.api.nvim_set_option_value("modifiable", true, { buf = type_popup.bufnr })
    render_types()

    -- If switching to suggestion and text is empty, pre-fill with suggestion syntax
    if type_keys[current_type_idx] == "suggestion" and current_line then
      local current_text = get_text()
      if current_text == "" then
        local suggestion_text = "```suggestion\n" .. current_line .. "\n```"
        local lines = vim.split(suggestion_text, "\n")
        vim.api.nvim_buf_set_lines(text_popup.bufnr, 0, -1, false, lines)
        -- Position cursor inside the suggestion block
        vim.api.nvim_win_set_cursor(text_popup.winid, { 2, 0 })
      end
    end
  end

  local function submit()
    local text = get_text()
    layout:unmount()
    if text and text ~= "" then
      callback(type_keys[current_type_idx], text)
    else
      callback(nil, nil)
    end
    restore_focus()
  end

  local function close()
    layout:unmount()
    callback(nil, nil)
    restore_focus()
  end

  layout:mount()
  render_types()

  -- Set initial text if provided
  if initial_text and initial_text ~= "" then
    local lines = vim.split(initial_text, "\n")
    vim.api.nvim_buf_set_lines(text_popup.bufnr, 0, -1, false, lines)
  end

  -- Focus the text popup and enter insert mode
  vim.api.nvim_set_current_win(text_popup.winid)
  vim.cmd("startinsert")

  -- TAB to cycle types
  vim.keymap.set({ "i", "n" }, "<Tab>", cycle_type, { buffer = text_popup.bufnr, noremap = true })

  -- C-s to submit from insert mode (Enter inserts newlines normally)
  vim.keymap.set("i", "<C-s>", submit, { buffer = text_popup.bufnr, noremap = true })

  -- Normal mode mappings
  vim.keymap.set("n", "<CR>", submit, { buffer = text_popup.bufnr, noremap = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = text_popup.bufnr, noremap = true })
  vim.keymap.set("n", "q", close, { buffer = text_popup.bufnr, noremap = true })
end

return M
