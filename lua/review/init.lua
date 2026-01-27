local M = {}

local config = require("review.config")
local highlights = require("review.highlights")
local hooks = require("review.hooks")
local keymaps = require("review.keymaps")
local store = require("review.store")
local export = require("review.export")
local comments = require("review.comments")
local file_export = require("review.file")

local initialized = false
local augroup = nil

---@param opts? ReviewConfig
function M.setup(opts)
  if initialized then
    return
  end

  config.setup(opts)
  highlights.setup()

  -- Set up autocmd to detect CodeDiff sessions
  augroup = vim.api.nvim_create_augroup("review", { clear = true })

  vim.api.nvim_create_autocmd("TabEnter", {
    group = augroup,
    callback = function()
      vim.defer_fn(function()
        M._check_codediff_session()
      end, 100)
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = augroup,
    callback = function()
      hooks.on_session_closed()
    end,
  })

  initialized = true
end

-- Check if current tab is a CodeDiff session and set up hooks/keymaps
function M._check_codediff_session()
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  local sess = lifecycle.get_session(tabpage)
  if not sess then
    return
  end

  -- Set up hooks
  hooks.on_session_created(tabpage)

  -- Set up keymaps (uses codediff's set_tab_keymap internally)
  keymaps.setup_keymaps(tabpage)
end

local function open_codediff_with_revisions(rev1, rev2)
  local ok, _ = pcall(require, "codediff")
  if not ok then
    vim.notify("codediff.nvim is required", vim.log.levels.ERROR, { title = "Review" })
    return
  end

  -- Load persisted comments (file wins when present)
  local cfg = config.get().export.file
  if cfg and cfg.enabled and cfg.import_on_open then
    local loaded_from_file = file_export.load_into_store()
    if not loaded_from_file then
      store.load()
    end
  else
    store.load()
  end

  -- Open CodeDiff
  if rev1 and rev2 then
    vim.cmd("CodeDiff " .. rev1 .. " " .. rev2)
  else
    vim.cmd("CodeDiff")
  end

  -- Wait for CodeDiff to initialize, then set up our hooks
  local attempts = 0
  local max_attempts = 5
  local function try_setup()
    attempts = attempts + 1
    local lifecycle_ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if lifecycle_ok then
      local tabpage = vim.api.nvim_get_current_tabpage()
      local sess = lifecycle.get_session(tabpage)
      if sess then
        M._check_codediff_session()
        return
      end
    end
    if attempts < max_attempts then
      vim.defer_fn(try_setup, 100)
    end
  end
  vim.defer_fn(try_setup, 200)
end

function M.open()
  open_codediff_with_revisions(nil, nil)
end

function M.open_commits()
  local picker = require("review.picker")
  picker.open(function(rev1, rev2)
    open_codediff_with_revisions(rev1, rev2)
  end)
end

function M.close_tab_only()
  vim.cmd("tabclose")
  hooks.on_session_closed()
end

function M.close()
  -- Export comments to clipboard before closing
  local count = store.count()
  if count > 0 then
    local markdown = export.generate_markdown()
    vim.fn.setreg("+", markdown)
    vim.fn.setreg("*", markdown)
    vim.notify(string.format("Exported %d comment(s) to clipboard", count), vim.log.levels.INFO, { title = "Review" })
  end

  -- Close the tab
  M.close_tab_only()
end

function M.export()
  export.to_clipboard()
end

function M.write()
  file_export.write_from_store({ copy = false, close = false })
end

function M.write_close()
  file_export.write_from_store({ copy = true, close = true })
end

function M.preview()
  export.preview()
end

function M.clear()
  store.clear()
  require("review.marks").clear_all()
  vim.notify("All comments cleared", vim.log.levels.INFO, { title = "Review" })
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
  cfg.codediff.readonly = not cfg.codediff.readonly

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return
  end

  local tabpage = hooks.get_current_tabpage()
  if not tabpage then
    return
  end

  local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)

  -- Update buffer readonly state
  if orig_buf and vim.api.nvim_buf_is_valid(orig_buf) then
    vim.api.nvim_set_option_value("modifiable", not cfg.codediff.readonly, { buf = orig_buf })
    vim.api.nvim_set_option_value("readonly", cfg.codediff.readonly, { buf = orig_buf })
  end
  if mod_buf and vim.api.nvim_buf_is_valid(mod_buf) then
    vim.api.nvim_set_option_value("modifiable", not cfg.codediff.readonly, { buf = mod_buf })
    vim.api.nvim_set_option_value("readonly", cfg.codediff.readonly, { buf = mod_buf })
  end

  -- Re-setup keymaps with new readonly state
  keymaps.clear_keymaps()
  keymaps.setup_keymaps(tabpage)

  local mode = cfg.codediff.readonly and "readonly" or "edit"
  vim.notify("Switched to " .. mode .. " mode", vim.log.levels.INFO, { title = "Review" })
end

return M
