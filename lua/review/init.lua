local M = {}

local config = require("review.config")
local highlights = require("review.highlights")
local hooks = require("review.hooks")
local keymaps = require("review.keymaps")
local storage = require("review.storage")
local store = require("review.store")
local export = require("review.export")
local comments = require("review.comments")

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

  -- Re-setup hooks when codediff recreates buffers (e.g. layout toggle)
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "CodeDiffOpen",
    callback = function()
      vim.defer_fn(function()
        M._check_codediff_session()
      end, 100)
    end,
  })

  -- On file selection, only refresh marks and keymaps — don't refocus
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "CodeDiffFileSelect",
    callback = function()
      vim.defer_fn(function()
        M._on_file_select()
      end, 100)
    end,
  })

  -- Notes live on ordinary files too: draw them whenever such a buffer shows up
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(ev)
      local file = hooks.plain_buffer_file(ev.buf)
      if not file then
        return
      end
      local orig_buf, mod_buf = hooks.get_buffers()
      if ev.buf == orig_buf or ev.buf == mod_buf then
        return -- the session hooks render these
      end
      store.load()
      if #store.get_for_file(file) > 0 then
        require("review.marks").render_for_buffer(ev.buf, "new", file)
      end
    end,
  })

  initialized = true
end

-- Handle file selection: refresh hooks/keymaps without stealing focus
function M._on_file_select()
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return
  end

  local tabpage = vim.api.nvim_get_current_tabpage()
  local sess = lifecycle.get_session(tabpage)
  if not sess then
    return
  end

  hooks.on_file_changed(tabpage)
  keymaps.setup_keymaps(tabpage)
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

---Comments made on another branch are still in the per-repo store; say so
---once so they don't end up in an export by surprise.
local function notify_other_branch_comments()
  local counts = store.count_from_other_branches(storage.git_branch())
  local parts = {}
  for branch, count in pairs(counts) do
    table.insert(parts, string.format("%d from %s", count, branch))
  end
  if #parts > 0 then
    table.sort(parts)
    vim.notify(
      "Comments made on other branches: " .. table.concat(parts, ", ") .. ". :Review clear archives and drops them.",
      vim.log.levels.WARN,
      { title = "review.nvim" }
    )
  end
end

---@param opts { args: string[] } :CodeDiff arguments
local function open_codediff(opts)
  local ok, _ = pcall(require, "codediff")
  if not ok then
    vim.notify("codediff.nvim is required", vim.log.levels.ERROR, { title = "review.nvim" })
    return
  end

  store.load()
  notify_other_branch_comments()

  vim.cmd({ cmd = "CodeDiff", args = opts.args })

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

local function open_codediff_with_revisions(rev1, rev2)
  if rev1 and rev2 then
    open_codediff({ args = { rev1, rev2 } })
  else
    open_codediff({ args = {} })
  end
end

---@return string|nil branch name, nil when not on a branch
local function current_branch()
  local result = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "HEAD" })
  if vim.v.shell_error ~= 0 or not result[1] or result[1] == "HEAD" then
    return nil
  end
  return result[1]
end

---True for the checked-out branch and for its upstream (origin/feature while
---on feature), so both review the working tree rather than the pushed commit.
---@param name string
---@return boolean
local function is_current_branch(name)
  if name == current_branch() then
    return true
  end
  local upstream = vim.fn.systemlist({ "git", "rev-parse", "--abbrev-ref", "@{upstream}" })[1]
  return vim.v.shell_error == 0 and name == upstream
end

---@param ref string
---@return boolean
local function ref_exists(ref)
  vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref .. "^{commit}" })
  return vim.v.shell_error == 0
end

---The branch a review is compared against: config.branch.base when set,
---else main or master, whichever exists (origin/HEAD breaks a tie).
---@return string|nil
local function default_base()
  local configured = config.get().branch.base
  if configured and configured ~= "" then
    return configured
  end
  local origin_head = vim.fn.systemlist({ "git", "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD" })[1]
  if vim.v.shell_error == 0 and origin_head then
    local name = origin_head:gsub("^origin/", "")
    if ref_exists(name) then
      return name
    end
  end
  for _, name in ipairs({ "main", "master" }) do
    if ref_exists(name) then
      return name
    end
  end
  return nil
end

---Review a branch against a base. With the checked-out branch as target the
---diff is `base...` (merge base vs working tree, so uncommitted work counts);
---with any other branch it's `base...target`, no checkout needed. Comments are
---stored per (base, target) pair, so they survive new commits.
---@param target? string branch to review; opens a picker when omitted
---@param base? string defaults to config.branch.base, main or master
function M.open_branch(target, base)
  local function open(chosen)
    base = base or default_base()
    if not base then
      vim.notify("No base branch found (set branch.base or create main/master)", vim.log.levels.WARN, { title = "review.nvim" })
      return
    end
    if chosen == base then
      vim.notify("Target and base are both " .. base, vim.log.levels.WARN, { title = "review.nvim" })
      return
    end
    local arg = is_current_branch(chosen) and (base .. "...") or (base .. "..." .. chosen)
    open_codediff({ args = { arg } })
  end

  if target then
    open(target)
    return
  end
  require("review.picker").open_branches(function(chosen)
    if chosen then
      open(chosen)
    end
  end)
end

function M.open()
  open_codediff_with_revisions(nil, nil)
end

function M.open_commits(rev1, rev2)
  if rev1 then
    open_codediff_with_revisions(rev2 and rev1 or (rev1 .. "^"), rev2 or rev1)
    return
  end
  local picker = require("review.picker")
  picker.open(function(r1, r2)
    open_codediff_with_revisions(r1, r2)
  end)
end

---Close the review: export, then (by default) archive and clear the comments
---so the next review starts empty. C and :Review export never clear.
function M.close()
  local markdown, count = export.deliver()
  local message = markdown and export.delivered_message(count) or nil

  vim.cmd("tabclose")
  hooks.on_session_closed()

  if markdown and config.get().export.clear_on_close ~= false then
    store.archive_and_clear()
    require("review.marks").clear_all()
    message = message .. ", archived and cleared"
  end
  if message then
    vim.notify(message, vim.log.levels.INFO, { title = "review.nvim" })
  end
end

function M.export()
  export.to_clipboard()
end

function M.preview()
  export.preview()
end

function M.clear()
  local archived = store.archive_and_clear()
  require("review.marks").clear_all()
  vim.notify(archived and "All comments archived and cleared" or "No comments to clear", vim.log.levels.INFO, { title = "review.nvim" })
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
  vim.notify("Switched to " .. mode .. " mode", vim.log.levels.INFO, { title = "review.nvim" })
end

return M
