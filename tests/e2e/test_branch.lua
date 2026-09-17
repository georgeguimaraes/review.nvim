-- :Review branch reviews a branch against its base using the merge base, so
-- commits that only landed on the base don't show up.
local H = dofile("tests/helpers.lua")
local eq, expect_match, expect_no_match = H.eq, H.expect_match, H.expect_no_match
local child = MiniTest.new_child_neovim()
local E = dofile("tests/e2e/helpers.lua")(child)

local sandbox = E.sandbox()

local function commit_file(dir, name, lines, message)
  vim.fn.writefile(lines, dir .. "/" .. name)
  E.git(dir, "add", ".")
  E.git(dir, "commit", "-q", "-m", message)
end

local API_BASE = { "local M = {}", "", "function M.a()", "  return 1", "end", "", "return M" }
local API_FEATURE = { "local M = {}", "", "function M.a()", "  if true then", "    return 2", "  end", "end", "", "return M" }

-- main: base commit (api.lua, utils.lua), then a commit touching only
-- main_only.lua after the branch point. feature: one commit changing api.lua.
-- Checked out: feature.
local function make_branch_repo()
  local dir = E.tempdir()
  E.git(dir, "init", "-q", "--initial-branch=main")
  vim.fn.writefile({ "return {}" }, dir .. "/utils.lua")
  commit_file(dir, "api.lua", API_BASE, "base")
  E.git(dir, "checkout", "-q", "-b", "feature")
  commit_file(dir, "api.lua", API_FEATURE, "feature work")
  E.git(dir, "checkout", "-q", "main")
  commit_file(dir, "main_only.lua", { "return 'only on main'" }, "main moved on")
  E.git(dir, "checkout", "-q", "feature")
  return dir
end

local repo

local function explorer()
  return child.lua_get(E.EXPLORER_TEXT)
end

local function current_branch()
  return vim.trim(E.git(repo, "rev-parse", "--abbrev-ref", "HEAD"))
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.fn.delete(sandbox .. "/data/nvim/review", "rf") -- stored comments must not leak between cases
      repo = make_branch_repo()
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

T["reviews the current branch against main using the merge base"] = function()
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  expect_match(explorer(), "api.lua", true)
  expect_no_match(explorer(), "main_only.lua", true)
end

T["picker lists the current branch first"] = function()
  child.cmd("Review branch")
  E.wait_for([[vim.api.nvim_win_get_config(0).relative ~= ""]], "branch picker")
  expect_match(child.api.nvim_get_current_line(), "^feature %(current%)")
  child.type_keys("<CR>")
  E.wait_ready("api.lua")
  expect_no_match(explorer(), "main_only.lua", true)
end

T["uncommitted work on the current branch is included"] = function()
  vim.fn.writefile({ "return { dirty = true }" }, repo .. "/utils.lua")
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  expect_match(explorer(), "utils.lua", true)
end

T["uncommitted work is included when the target is the current branch's upstream"] = function()
  local remote = E.tempdir()
  E.git(repo, "clone", "-q", "--bare", repo, remote)
  E.git(repo, "remote", "add", "origin", remote)
  E.git(repo, "fetch", "-q", "origin")
  E.git(repo, "remote", "set-head", "origin", "main") -- the bare clone's HEAD was feature, and origin/HEAD is the default base
  E.git(repo, "branch", "-q", "--set-upstream-to=origin/feature")
  vim.fn.writefile({ "return { dirty = true }" }, repo .. "/utils.lua")
  child.cmd("Review branch origin/feature")
  E.wait_ready("api.lua")
  expect_match(explorer(), "utils.lua", true)
  vim.fn.delete(remote, "rf")
end

T["reviews another branch without checking it out"] = function()
  E.git(repo, "checkout", "-q", "main")
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  expect_match(explorer(), "api.lua", true)
  expect_no_match(explorer(), "main_only.lua", true)
  eq(current_branch(), "main")
  eq(vim.fn.readfile(repo .. "/api.lua"), API_BASE)
end

-- Record what :CodeDiff was asked to diff.
local RECORD_CODEDIFF_ARGS = [[
  local orig = vim.api.nvim_cmd
  vim.api.nvim_cmd = function(cmd, opts)
    if cmd.cmd == "CodeDiff" then _G.CODEDIFF_ARGS = cmd.args end
    return orig(cmd, opts or {})
  end
]]

T["diffs the merge base of the configured base and the working tree"] = function()
  child.lua(RECORD_CODEDIFF_ARGS)
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  eq(child.lua_get([[_G.CODEDIFF_ARGS]]), { "main..." })
end

T["honours branch.base from config"] = function()
  E.git(repo, "branch", "-q", "develop", "main~1")
  child.lua([[require("review.config").setup({ branch = { base = "develop" } })]])
  child.lua(RECORD_CODEDIFF_ARGS)
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  eq(child.lua_get([[_G.CODEDIFF_ARGS]]), { "develop..." })
end

T["warns about comments made on another branch"] = function()
  child.cmd("Review branch feature")
  E.wait_ready("api.lua")
  child.type_keys("4G", "i")
  E.wait_for(E.IN_POPUP, "popup")
  child.type_keys("made on feature", "<C-s>")
  E.wait_for([[require("review.store").count() == 1]], "comment stored")
  child.lua([[require("review.config").get().export.clear_on_close = false]])
  child.type_keys("q")
  E.wait_for([[vim.fn.tabpagenr("$") == 1]], "review closed")
  eq(child.lua_get([[require("review.store").count()]]), 1)

  E.git(repo, "checkout", "-q", "main")
  vim.fn.writefile({ "-- edited on main", "return 'only on main'" }, repo .. "/main_only.lua") -- something to review on main
  child.cmd("Review")
  E.wait_ready("main_only.lua")
  expect_match(child.lua_get([[vim.fn.execute("messages")]]), "1 from feature", true)
end

return T
