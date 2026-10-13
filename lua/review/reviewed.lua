-- Files marked as reviewed. A mark is keyed by the path and the blobs on both
-- sides of the diff, so it stops matching as soon as either side changes.
local M = {}

local storage = require("review.storage")
local hooks = require("review.hooks")

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "review.nvim" })
end

---@type table<string, number>|nil reviewed_at by mark key
local marks = nil

local function get_marks()
  if not marks then
    marks = storage.load_reviewed()
  end
  return marks
end

---The two sides codediff compares for a file (codediff/ui/refresh/panel.lua),
---as `git cat-file` specs. nil means the working tree.
---@param data table explorer data
---@param file { path: string, old_path?: string, group: string }
---@return string old, string|nil new
function M.sides(data, file)
  local old_path = file.old_path or file.path
  if file.group == "conflicts" then
    return ":2:" .. file.path, ":3:" .. file.path
  elseif data.base_revision then
    local target = data.target_revision
    local new = (target and target ~= "WORKING") and (target .. ":" .. file.path) or nil
    return data.base_revision .. ":" .. old_path, new
  elseif file.group == "staged" then
    return "HEAD:" .. old_path, ":0:" .. file.path
  end
  return ":0:" .. file.path, nil
end

---@param git_root string
---@param specs string[]
---@return table<string, string> blob (or "missing") by spec
local function blobs_for_specs(git_root, specs)
  local blobs = {}
  if #specs == 0 then
    return blobs
  end
  local out = vim.fn.systemlist({ "git", "-C", git_root, "cat-file", "--batch-check=%(objectname)" }, specs)
  for i, spec in ipairs(specs) do
    blobs[spec] = (out[i] or ""):match("^%x+$") or "missing"
  end
  return blobs
end

---@param git_root string
---@param paths string[]
---@return table<string, string> blob (or "missing") by path
local function blobs_for_worktree(git_root, paths)
  local blobs, existing = {}, {}
  for _, path in ipairs(paths) do
    local stat = vim.uv.fs_stat(git_root .. "/" .. path)
    if stat and stat.type == "file" then
      table.insert(existing, path)
    else
      blobs[path] = "missing"
    end
  end
  if #existing > 0 then
    local out = vim.fn.systemlist({ "git", "-C", git_root, "hash-object", "--stdin-paths" }, existing)
    for i, path in ipairs(existing) do
      blobs[path] = (out[i] or ""):match("^%x+$") or "missing"
    end
  end
  return blobs
end

-- Mark keys for every file in the explorer, computed once per event-loop
-- tick: an explorer render asks for each row in the same tick.
local memo = nil

---@param explorer table
---@return table<string, string> mark key by group and path
local function keys_for(explorer)
  if memo and memo.explorer == explorer then
    return memo.keys
  end
  local data = explorer.data
  local files = {}
  for _, group in ipairs({ "unstaged", "staged", "conflicts" }) do
    for _, file in ipairs((data.status_result or {})[group] or {}) do
      table.insert(files, { path = file.path, old_path = file.old_path, group = group })
    end
  end

  local specs, worktree, sides = {}, {}, {}
  for i, file in ipairs(files) do
    local old, new = M.sides(data, file)
    sides[i] = { old, new }
    table.insert(specs, old)
    if new then
      table.insert(specs, new)
    else
      table.insert(worktree, file.path)
    end
  end
  local spec_blobs = blobs_for_specs(data.git_root, specs)
  local worktree_blobs = blobs_for_worktree(data.git_root, worktree)

  local keys = {}
  for i, file in ipairs(files) do
    local old, new = sides[i][1], sides[i][2]
    local new_blob = new and spec_blobs[new] or worktree_blobs[file.path]
    keys[file.group .. "\0" .. file.path] = string.format("%s %s %s", spec_blobs[old], new_blob, file.path)
  end

  memo = { explorer = explorer, keys = keys }
  vim.schedule(function()
    memo = nil
  end)
  return keys
end

---@param explorer table
---@param file { path: string, group: string }
---@return boolean
function M.is_reviewed(explorer, file)
  if not explorer.data.git_root or next(get_marks()) == nil then
    return false
  end
  local key = keys_for(explorer)[file.group .. "\0" .. file.path]
  return key ~= nil and get_marks()[key] ~= nil
end

local function redraw(explorer)
  if explorer.bufnr and vim.api.nvim_buf_is_valid(explorer.bufnr) and not explorer.is_hidden then
    explorer.tree:render()
  end
end

---Files in the order the explorer shows them (what <Tab> walks).
local function visible_files(explorer)
  local files = {}
  for _, entry in ipairs(require("codediff.ui.explorer.tree").get_all_files(explorer.tree)) do
    table.insert(files, entry.data)
  end
  return files
end

local function current_index(explorer, files)
  local data = explorer.data
  for i, file in ipairs(files) do
    if file.path == data.current_file_path and file.group == data.current_file_group then
      return i
    end
  end
  return nil
end

local function progress(explorer, files)
  local done = 0
  for _, file in ipairs(files) do
    if M.is_reviewed(explorer, file) then
      done = done + 1
    end
  end
  return done, #files
end

---Go to the next (or previous) file that is not reviewed. Returns false when
---no file in the review is marked, so the caller can use codediff's own
---navigation.
---@param explorer table
---@param direction "next"|"prev"
---@return boolean handled, boolean moved
function M.skip_to_unreviewed(explorer, direction)
  if not explorer.data.git_root then
    return false, false
  end
  local files = visible_files(explorer)
  local any = false
  for _, file in ipairs(files) do
    if M.is_reviewed(explorer, file) then
      any = true
      break
    end
  end
  if not any then
    return false, false
  end

  local n = #files
  local step = direction == "prev" and -1 or 1
  local cur = current_index(explorer, files)
  local start = cur or (step == 1 and 0 or n + 1)
  for k = 1, cur and n - 1 or n do
    local i = (start - 1 + step * k) % n + 1
    if not M.is_reviewed(explorer, files[i]) then
      explorer.on_file_select(files[i])
      return true, true
    end
  end

  if cur and not M.is_reviewed(explorer, files[cur]) then
    notify("No other unreviewed files")
  else
    notify(string.format("All files reviewed (%d/%d)", n, n))
  end
  return true, false
end

---Mark the current file as reviewed and go to the next unreviewed one, or
---unmark it when it is already reviewed.
---@param explorer table
---@return boolean moved
function M.toggle_current(explorer)
  if not explorer.data.git_root then
    notify("Marking files as reviewed needs a git repository", vim.log.levels.WARN)
    return false
  end
  local files = visible_files(explorer)
  local cur = current_index(explorer, files)
  local file = cur and files[cur] or explorer.data.current_selection
  if not file then
    return false
  end
  local key = keys_for(explorer)[file.group .. "\0" .. file.path]
  if not key then
    return false
  end

  local all = get_marks()
  if all[key] then
    all[key] = nil
    storage.save_reviewed(all)
    redraw(explorer)
    notify(string.format("Unmarked %s (%d/%d reviewed)", file.path, progress(explorer, files)))
    return false
  end

  all[key] = os.time()
  storage.save_reviewed(all)
  redraw(explorer)
  notify(string.format("Reviewed %s (%d/%d)", file.path, progress(explorer, files)))
  local _, moved = M.skip_to_unreviewed(explorer, "next")
  return moved
end

---Forget all marks (the sidecar file is removed with the comment store).
function M.reset()
  marks = nil
  local explorer = hooks.get_explorer(vim.api.nvim_get_current_tabpage())
  if explorer then
    redraw(explorer)
  end
end

local wrapper = nil

---Show a check mark on reviewed rows of codediff's file panel. codediff reads
---the formatter on every render, and its setup replaces the options table,
---so this runs again on each review session.
local function install_formatter()
  local ok_cfg, cfg = pcall(require, "codediff.config")
  local ok_defaults, defaults = pcall(require, "codediff.ui.explorer.formatters")
  if not (ok_cfg and ok_defaults) or not (cfg.options and cfg.options.explorer) then
    return
  end
  local formatters = cfg.options.explorer.formatters or {}
  cfg.options.explorer.formatters = formatters
  if wrapper and formatters.file == wrapper then
    return
  end
  local inner = formatters.file or defaults.file
  wrapper = function(ctx)
    local layout = inner(ctx)
    local explorer = hooks.get_explorer(vim.api.nvim_get_current_tabpage())
    if explorer and M.is_reviewed(explorer, ctx) then
      layout = vim.tbl_extend("force", {}, layout)
      layout.right = { { segments = { { text = "✓ ", hl = "ReviewReviewed" } } }, unpack(layout.right or {}) }
    end
    return layout
  end
  formatters.file = wrapper
end

---Hook into a review session. The explorer has already rendered once without
---the formatter, so redraw it when there are marks to show.
---@param tabpage number
function M.attach(tabpage)
  install_formatter()
  local explorer = hooks.get_explorer(tabpage)
  if explorer and next(get_marks()) ~= nil then
    redraw(explorer)
  end
end

return M
