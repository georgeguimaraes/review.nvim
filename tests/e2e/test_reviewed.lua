-- Marking files as reviewed: r marks and moves on, <Tab> skips reviewed files,
-- ]f still visits every file, and a mark drops when the file changes.
local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match
local child = MiniTest.new_child_neovim()
local E = dofile("tests/e2e/helpers.lua")(child)

local sandbox = E.sandbox()

local FILES = { "a.lua", "b.lua", "c.lua" }

local function make_repo()
  local dir = E.tempdir()
  for _, name in ipairs(FILES) do
    vim.fn.writefile({ "local M = {}", "", "return M" }, dir .. "/" .. name)
  end
  E.git(dir, "init", "-q", "--initial-branch=main")
  E.git(dir, "add", ".")
  E.git(dir, "commit", "-q", "-m", "init")
  for _, name in ipairs(FILES) do
    vim.fn.writefile({ "local M = {}", "", "M.changed = true", "", "return M" }, dir .. "/" .. name)
  end
  return dir
end

---The explorer row for `name`, so tests can look for the check mark on it.
local function row(name)
  for _, line in ipairs(vim.split(child.lua_get(E.EXPLORER_TEXT), "\n")) do
    if line:find(name, 1, true) then
      return line
    end
  end
  return ""
end

local function reviewed_rows()
  local rows = {}
  for _, name in ipairs(FILES) do
    if row(name):find("✓", 1, true) then
      table.insert(rows, name)
    end
  end
  return table.concat(rows, ",")
end

---The explorer row under the explorer window's cursor.
local function explorer_cursor_row()
  return child.lua_get([[(function()
    local e = require("review.hooks").get_explorer(vim.api.nvim_get_current_tabpage())
    local line = vim.api.nvim_win_get_cursor(e.winid)[1]
    return vim.api.nvim_buf_get_lines(e.bufnr, line - 1, line, false)[1]
  end)()]])
end

local repo

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.fn.delete(sandbox .. "/data/nvim/review", "rf")
      repo = make_repo()
      E.restart(repo)
    end,
    post_case = function()
      if repo then
        vim.fn.delete(repo, "rf")
      end
    end,
    post_once = function()
      child.stop()
      vim.fn.delete(sandbox, "rf")
    end,
  },
})

local function open_review()
  child.cmd("Review")
  E.wait_ready("a.lua")
end

T["r marks the file and moves to the next one"] = function()
  open_review()
  child.type_keys("r")
  E.wait_ready("b.lua")
  E.wait_for(string.format([[(%s):find("✓", 1, true) ~= nil]], E.EXPLORER_TEXT), "check mark")
  eq(reviewed_rows(), "a.lua")
end

T["<Tab> skips reviewed files and ]f does not"] = function()
  open_review()
  child.type_keys("]f")
  E.wait_ready("b.lua")
  child.type_keys("r") -- marks b.lua, moves to c.lua
  E.wait_ready("c.lua")
  child.type_keys("]f")
  E.wait_ready("a.lua")

  child.type_keys("<Tab>")
  E.wait_ready("c.lua")
  expect_match(explorer_cursor_row(), "c%.lua")

  child.type_keys("]f") -- wraps to a.lua
  E.wait_ready("a.lua")
  child.type_keys("]f")
  E.wait_ready("b.lua")
  eq(reviewed_rows(), "b.lua")
end

T["a mark drops when the file changes"] = function()
  open_review()
  child.type_keys("r")
  E.wait_ready("b.lua")
  eq(reviewed_rows(), "a.lua")

  vim.fn.writefile({ "local M = {}", "", "M.changed = 2", "", "return M" }, repo .. "/a.lua")
  -- codediff only re-renders when the file list changes; any render picks up the new blobs
  child.lua([[require("review.hooks").get_explorer(vim.api.nvim_get_current_tabpage()).tree:render()]])
  E.wait_for(string.format([[(%s):find("✓", 1, true) == nil]], E.EXPLORER_TEXT), "check mark gone")

  -- The next save drops the stale mark of a.lua
  child.type_keys("r")
  E.wait_for([[vim.tbl_count(require("review.storage").load_reviewed()) == 1]], "stale mark pruned")
  eq(reviewed_rows(), "b.lua")
end

T["r on the last file says all files are reviewed, and :Review clear drops the marks"] = function()
  open_review()
  child.type_keys("r")
  E.wait_ready("b.lua")
  child.type_keys("r")
  E.wait_ready("c.lua")
  child.type_keys("r")
  E.wait_for([[vim.fn.execute("messages"):find("All files reviewed (3/3)", 1, true) ~= nil]], "all reviewed message")
  eq(child.lua_get([[require("review.hooks").get_cursor_position()]]), "c.lua")
  eq(reviewed_rows(), "a.lua,b.lua,c.lua")

  child.cmd("Review clear")
  E.wait_for(string.format([[(%s):find("✓", 1, true) == nil]], E.EXPLORER_TEXT), "marks cleared")
  E.wait_for([[vim.fn.execute("messages"):find("Reviewed marks cleared", 1, true) ~= nil]], "clear message")
end

T["marks persist across restarts"] = function()
  open_review()
  child.type_keys("r")
  E.wait_ready("b.lua")
  E.restart(repo)
  open_review()
  E.wait_for(string.format([[(%s):find("✓", 1, true) ~= nil]], E.EXPLORER_TEXT), "check mark after restart")
  eq(reviewed_rows(), "a.lua")
end

-- Revision mode: the old side comes from the base commit and the new side from
-- the target commit or the working tree.
local function make_branch_repo()
  local dir = E.tempdir()
  E.git(dir, "init", "-q", "--initial-branch=main")
  vim.fn.writefile({ "local M = {}", "", "return M" }, dir .. "/api.lua")
  vim.fn.writefile({ "local M = {}", "", "return M" }, dir .. "/utils.lua")
  E.git(dir, "add", ".")
  E.git(dir, "commit", "-q", "-m", "base")
  E.git(dir, "checkout", "-q", "-b", "feature")
  vim.fn.writefile({ "local M = {}", "", "M.x = 2", "", "return M" }, dir .. "/api.lua")
  vim.fn.writefile({ "local M = {}", "", "M.x = 2", "", "return M" }, dir .. "/utils.lua")
  E.git(dir, "commit", "-q", "-am", "feature work")
  return dir
end

for _, case in ipairs({
  { name = "current branch (working tree side)", checkout = "feature" },
  { name = "another branch (commit side)", checkout = "main" },
}) do
  T["revision mode marks and skips: " .. case.name] = function()
    vim.fn.delete(repo, "rf")
    repo = make_branch_repo()
    E.git(repo, "checkout", "-q", case.checkout)
    E.restart(repo)
    child.cmd("Review branch feature")
    E.wait_ready("api.lua")
    child.type_keys("r")
    E.wait_ready("utils.lua")
    E.wait_for(string.format([[(%s):find("✓", 1, true) ~= nil]], E.EXPLORER_TEXT), "check mark")
    expect_match(row("api.lua"), "✓")

    child.type_keys("<Tab>") -- api.lua is reviewed, so there is nowhere else to go
    E.wait_for([[vim.fn.execute("messages"):find("No other unreviewed files", 1, true) ~= nil]], "nowhere to go")
    eq(child.lua_get([[require("review.hooks").get_cursor_position()]]), "utils.lua")
  end
end

return T
