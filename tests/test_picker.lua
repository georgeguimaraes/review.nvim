local H = dofile("tests/helpers.lua")
local eq = H.eq

local picker = require("review.picker")

local function git(dir, ...)
  local cmd = { "git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", ... }
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error("git failed: " .. table.concat(cmd, " ") .. "\n" .. out)
  end
end

-- Commits within a test land in the same second, so pin the committer date
-- to make "most recent first" deterministic.
local function commit(dir, name, date)
  vim.fn.writefile({ name }, dir .. "/" .. name)
  git(dir, "add", ".")
  vim.fn.setenv("GIT_COMMITTER_DATE", date or "2026-01-01T00:00:00")
  git(dir, "commit", "-q", "-m", name)
  vim.fn.setenv("GIT_COMMITTER_DATE", nil)
end

local repo

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      repo = vim.fn.tempname()
      vim.fn.mkdir(repo, "p")
      git(repo, "init", "-q", "--initial-branch=main")
      commit(repo, "base")
    end,
    post_case = function()
      vim.fn.delete(repo, "rf")
    end,
  },
})

T["list_branches"] = MiniTest.new_set()

T["list_branches"]["puts the checked-out branch first, then others by recency"] = function()
  git(repo, "checkout", "-q", "-b", "feature")
  commit(repo, "feature-work", "2026-01-02T00:00:00")
  git(repo, "checkout", "-q", "-b", "topic/newest")
  commit(repo, "newest-work", "2026-01-03T00:00:00") -- most recent, sorts before main
  git(repo, "checkout", "-q", "feature")

  local branches = picker.list_branches(repo)
  eq(vim.tbl_map(function(b) return b.name end, branches), { "feature", "topic/newest", "main" })
  eq(vim.tbl_map(function(b) return b.current end, branches), { true, false, false })
end

T["list_branches"]["carries the last commit subject and a relative date"] = function()
  local branches = picker.list_branches(repo)
  eq(#branches, 1)
  eq(branches[1].name, "main")
  eq(branches[1].subject, "base")
  eq(branches[1].date ~= "", true)
end

T["list_branches"]["skips the remote HEAD pointer"] = function()
  local remote = vim.fn.tempname()
  git(repo, "clone", "-q", "--bare", repo, remote)
  git(repo, "remote", "add", "origin", remote)
  git(repo, "fetch", "-q", "origin")
  git(repo, "remote", "set-head", "origin", "main")

  eq(vim.tbl_map(function(b) return b.name end, picker.list_branches(repo)), { "main", "origin/main" })
  vim.fn.delete(remote, "rf")
end

return T
