local M = {}

local config = require("review.config")

---@param initial_type? "note"|"suggestion"|"issue"|"praise"
---@param initial_text? string
---@param callback fun(comment_type: string|nil, text: string|nil)
function M.open(initial_type, initial_text, callback)
  local ok_input, Input = pcall(require, "nui.input")
  local ok_popup, Popup = pcall(require, "nui.popup")
  local ok_layout, Layout = pcall(require, "nui.layout")

  if not (ok_input and ok_popup and ok_layout) then
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
  local type_keys = { "note", "suggestion", "issue", "praise" }
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

  -- Input popup (bottom)
  local input = Input({
    border = {
      style = "rounded",
      text = {
        top = " Comment ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = "> ",
    default_value = initial_text or "",
    on_submit = function(value)
      if value and value ~= "" then
        callback(type_keys[current_type_idx], value)
      else
        callback(nil, nil)
      end
      restore_focus()
    end,
    on_close = function()
      callback(nil, nil)
      restore_focus()
    end,
  })

  local layout = Layout(
    {
      position = "50%",
      size = {
        width = 60,
        height = 6,
      },
    },
    Layout.Box({
      Layout.Box(type_popup, { size = 3 }),
      Layout.Box(input, { size = 3 }),
    }, { dir = "col" })
  )

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

    -- Center the text
    vim.api.nvim_set_option_value("modifiable", false, { buf = type_popup.bufnr })
  end

  local function cycle_type()
    current_type_idx = current_type_idx % #type_keys + 1
    vim.api.nvim_set_option_value("modifiable", true, { buf = type_popup.bufnr })
    render_types()
  end

  layout:mount()
  render_types()

  -- TAB to cycle types
  input:map("i", "<Tab>", cycle_type, { noremap = true })
  input:map("n", "<Tab>", cycle_type, { noremap = true })

  -- Close mappings
  input:map("n", "<Esc>", function()
    layout:unmount()
  end, { noremap = true })

  input:map("n", "q", function()
    layout:unmount()
  end, { noremap = true })
end

return M
