local M = {}

local config = require("diffnotes.config")
local highlights = require("diffnotes.highlights")
local hooks = require("diffnotes.hooks")
local keymaps = require("diffnotes.keymaps")
local store = require("diffnotes.store")
local export = require("diffnotes.export")
local comments = require("diffnotes.comments")

local initialized = false

---@param opts? DiffnotesConfig
function M.setup(opts)
  if initialized then
    return
  end

  config.setup(opts)
  highlights.setup()

  initialized = true
end

function M.open()
  local ok, diffview = pcall(require, "diffview")
  if not ok then
    vim.notify("diffview.nvim is required", vim.log.levels.ERROR, { title = "Diffnotes" })
    return
  end

  -- Load persisted comments
  store.load()

  local dv_hooks = hooks.get_diffview_hooks()
  local dv_keymaps = keymaps.get_diffview_keymaps()

  -- File panel keymaps: Enter selects and focuses content
  local file_panel_keymaps = {
    {
      "n", "<cr>",
      function()
        local actions = require("diffview.actions")
        actions.select_entry()
        vim.defer_fn(function()
          actions.focus_entry()
        end, 10)
      end,
      { desc = "Select and focus file" },
    },
    {
      "n", "<Tab>",
      function()
        local actions = require("diffview.actions")
        actions.select_next_entry()
        vim.defer_fn(function()
          actions.focus_entry()
        end, 10)
      end,
      { desc = "Next file" },
    },
    {
      "n", "<S-Tab>",
      function()
        local actions = require("diffview.actions")
        actions.select_prev_entry()
        vim.defer_fn(function()
          actions.focus_entry()
        end, 10)
      end,
      { desc = "Previous file" },
    },
    { "n", "q", function() M.close() end, { desc = "Close" } },
  }

  diffview.setup({
    hooks = dv_hooks,
    keymaps = {
      view = dv_keymaps,
      diff1 = dv_keymaps,
      diff2 = dv_keymaps,
      diff3 = dv_keymaps,
      diff4 = dv_keymaps,
      file_panel = file_panel_keymaps,
    },
  })

  vim.cmd("DiffviewOpen")

  -- Focus first file and switch to unified layout
  vim.defer_fn(function()
    local actions = require("diffview.actions")
    actions.select_entry()
    vim.defer_fn(function()
      actions.focus_entry()
      -- Convert all files to unified (Diff1) layout
      vim.defer_fn(function()
        local lib = require("diffview.lib")
        local view = lib.get_current_view()
        if not view then return end

        local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
        local files = {}
        if view.panel and view.panel.files then
          if view.panel.files.working then vim.list_extend(files, view.panel.files.working) end
          if view.panel.files.staged then vim.list_extend(files, view.panel.files.staged) end
        end
        for _, entry in ipairs(files) do
          entry:convert_layout(Diff1)
        end
      end, 50)
    end, 50)
  end, 100)
end

function M.close()
  -- Export comments to clipboard before closing
  local count = store.count()
  if count > 0 then
    local markdown = export.generate_markdown()
    vim.fn.setreg("+", markdown)
    vim.fn.setreg("*", markdown)
    vim.notify(string.format("Exported %d comment(s) to clipboard", count), vim.log.levels.INFO, { title = "Diffnotes" })
  end
  vim.cmd("DiffviewClose")
end

function M.export()
  export.to_clipboard()
end

function M.preview()
  export.preview()
end

function M.clear()
  store.clear()
  require("diffnotes.marks").clear_all()
  vim.notify("All comments cleared", vim.log.levels.INFO, { title = "Diffnotes" })
end

function M.count()
  return store.count()
end

function M.add_note()
  comments.add_at_cursor("note")
end

function M.add_suggestion()
  comments.add_at_cursor("suggestion")
end

function M.add_issue()
  comments.add_at_cursor("issue")
end

function M.add_praise()
  comments.add_at_cursor("praise")
end

function M.toggle_readonly()
  local cfg = config.get()
  cfg.diffview.readonly = not cfg.diffview.readonly

  -- Re-apply keymaps by closing and reopening
  local ok, lib = pcall(require, "diffview.lib")
  if ok then
    local view = lib.get_current_view()
    if view then
      -- Refresh diffview with new keymaps
      local dv_hooks = hooks.get_diffview_hooks()
      local dv_keymaps = keymaps.get_diffview_keymaps()

      require("diffview").setup({
        hooks = dv_hooks,
        keymaps = {
          view = dv_keymaps,
          diff1 = dv_keymaps,
          diff2 = dv_keymaps,
          diff3 = dv_keymaps,
          diff4 = dv_keymaps,
        },
      })

      -- Update buffer readonly state
      if view.cur_layout then
        local wins = { view.cur_layout.a, view.cur_layout.b, view.cur_layout.c, view.cur_layout.d }
        for _, win in ipairs(wins) do
          if win and win.file and win.file.bufnr and vim.api.nvim_buf_is_valid(win.file.bufnr) then
            vim.api.nvim_set_option_value("modifiable", not cfg.diffview.readonly, { buf = win.file.bufnr })
            vim.api.nvim_set_option_value("readonly", cfg.diffview.readonly, { buf = win.file.bufnr })
          end
        end
      end
    end
  end

  local mode = cfg.diffview.readonly and "readonly" or "edit"
  vim.notify("Switched to " .. mode .. " mode", vim.log.levels.INFO, { title = "Diffnotes" })
end

function M.toggle_layout()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    vim.notify("diffview.nvim is required", vim.log.levels.ERROR, { title = "Diffnotes" })
    return
  end

  local view = lib.get_current_view()
  if not view then
    return
  end

  -- Get layout classes
  local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
  local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
  local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver

  -- Custom cycle: horizontal -> vertical -> single -> horizontal
  local layouts = { Diff2Hor, Diff2Ver, Diff1 }

  local cur_file = view.cur_entry
  if not cur_file then
    return
  end

  -- Get all files to update
  local files = {}
  if view.panel and view.panel.files then
    if view.panel.files.working then
      vim.list_extend(files, view.panel.files.working)
    end
    if view.panel.files.staged then
      vim.list_extend(files, view.panel.files.staged)
    end
  end

  -- Find current layout and get next
  local cur_layout = cur_file.layout
  local cur_idx = 1
  for i, layout in ipairs(layouts) do
    if cur_layout:instanceof(layout) then
      cur_idx = i
      break
    end
  end
  local next_layout = layouts[(cur_idx % #layouts) + 1]

  -- Convert all files to new layout
  for _, entry in ipairs(files) do
    entry:convert_layout(next_layout)
  end

  -- Restore cursor position
  vim.defer_fn(function()
    local main = view.cur_layout:get_main_win()
    if main and main.id and vim.api.nvim_win_is_valid(main.id) then
      vim.api.nvim_set_current_win(main.id)
    end
  end, 10)
end

return M
