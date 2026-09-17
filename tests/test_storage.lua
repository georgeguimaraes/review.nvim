local H = dofile("tests/helpers.lua")
local eq, neq, expect_truthy = H.eq, H.neq, H.expect_truthy

local storage = require("review.storage")

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      storage.clear_revisions()
    end,
  },
})

T["get_storage_path"] = MiniTest.new_set()

T["get_storage_path"]["returns branch-scoped path when no revisions set"] = function()
  storage.clear_revisions()
  local path = storage.get_storage_path()
  neq(path, nil)
  eq(path:match("_"), nil)
  expect_truthy(path:match("%.json$"))
end

T["get_storage_path"]["returns revision-scoped path when revisions are set"] = function()
  storage.set_revisions("abc12345def^", "fef98765abc")
  local path = storage.get_storage_path()
  neq(path, nil)
  expect_truthy(path:match("abc12345_fef98765%.json$"))
end

T["get_storage_path"]["strips trailing ^ from revision in filename"] = function()
  storage.set_revisions("abc12345^", "def67890")
  local path = storage.get_storage_path()
  expect_truthy(path:match("abc12345_def67890%.json$"))
end

T["get_storage_path"]["truncates long revisions to 8 chars"] = function()
  storage.set_revisions("abcdef1234567890^", "1234567890abcdef")
  local path = storage.get_storage_path()
  expect_truthy(path:match("abcdef12_12345678%.json$"))
end

T["get_storage_path"]["keeps branch names readable and filename-safe"] = function()
  storage.set_revisions("feature/login-form", "main")
  local path = storage.get_storage_path()
  expect_truthy(path:match("feature_login%-form_main%.json$"))
end

T["get_storage_path"]["returns branch path after clearing revisions"] = function()
  storage.set_revisions("abc12345^", "def67890")
  storage.clear_revisions()
  local path = storage.get_storage_path()
  neq(path, nil)
  -- Should not contain revision separator
  eq(path:match("abc12345"), nil)
end

return T
