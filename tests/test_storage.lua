local H = dofile("tests/helpers.lua")
local eq, neq, expect_match, expect_truthy = H.eq, H.neq, H.expect_match, H.expect_truthy

local storage = require("review.storage")

local function reset_disk()
  storage.clear()
  vim.fn.delete(storage.archive_dir(), "rf")
  local legacy = storage.legacy_storage_path()
  if legacy then
    vim.fn.delete(legacy)
  end
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = reset_disk,
    post_once = reset_disk,
  },
})

T["get_storage_path"] = MiniTest.new_set()

T["get_storage_path"]["is one file per repository, not per branch"] = function()
  local path = storage.get_storage_path()
  neq(path, nil)
  expect_match(path, "/review/%x+%.json$")
  eq(path:find(storage.git_branch(), 1, true), nil)
end

T["get_storage_path"]["legacy path carried the branch name"] = function()
  local legacy = storage.legacy_storage_path()
  local safe_branch = storage.git_branch():gsub("[^%w%-_]", "_")
  expect_match(legacy, "/review/%x+%-" .. vim.pesc(safe_branch) .. "%.json$")
end

T["archive"] = MiniTest.new_set()

T["archive"]["moves the live file into archive/ and keeps its contents"] = function()
  storage.save({ ["a.lua"] = { { file = "a.lua", line = 1, type = "note", text = "keep me" } } })
  local archived = storage.archive()
  neq(archived, nil)
  expect_match(archived, "/review/archive/%x+%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%.json$")
  eq(vim.fn.filereadable(storage.get_storage_path()), 0)
  expect_match(table.concat(vim.fn.readfile(archived), "\n"), "keep me", true)
end

T["archive"]["returns nil when there is nothing to archive"] = function()
  eq(storage.archive(), nil)
  eq(vim.fn.isdirectory(storage.archive_dir()), 0)
end

T["load"] = MiniTest.new_set()

T["load"]["adopts the old per-branch file on first run"] = function()
  vim.fn.writefile({ '{"b.lua":[{"file":"b.lua","line":2,"type":"issue","text":"from before"}]}' }, storage.legacy_storage_path())
  local data = storage.load()
  eq(data["b.lua"][1].text, "from before")
  eq(vim.fn.filereadable(storage.get_storage_path()), 1)
end

T["load"]["returns an empty table when nothing is stored"] = function()
  eq(storage.load(), {})
end

T["cleanup_expired"] = MiniTest.new_set()

T["cleanup_expired"]["drops old archives and never the live file"] = function()
  storage.save({})
  local live = storage.get_storage_path()
  vim.fn.mkdir(storage.archive_dir(), "p")
  local old = storage.archive_dir() .. "/old.json"
  local fresh = storage.archive_dir() .. "/fresh.json"
  vim.fn.writefile({ "{}" }, old)
  vim.fn.writefile({ "{}" }, fresh)
  vim.fn.system({ "touch", "-t", "202001010000", old, live })
  storage.cleanup_expired()
  eq(vim.fn.filereadable(old), 0)
  eq(vim.fn.filereadable(fresh), 1)
  eq(vim.fn.filereadable(live), 1)
end

return T
