local H = dofile("tests/helpers.lua")
local expect_match, expect_no_match = H.expect_match, H.expect_no_match

local store = require("review.store")
local export = require("review.export")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
    end,
  },
})

T["generate_markdown"] = MiniTest.new_set()

T["generate_markdown"]["returns empty message when no comments"] = function()
  local md = export.generate_markdown()
  expect_match(md, "No comments yet")
end

T["generate_markdown"]["includes file and comment in output"] = function()
  store.add("src/main.lua", 10, "issue", "Fix this bug")

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:10")
  expect_match(md, "%[ISSUE%]")
  expect_match(md, "Fix this bug")
end

T["generate_markdown"]["formats comments as numbered list"] = function()
  store.add("a.lua", 1, "note", "Note A")
  store.add("b.lua", 1, "issue", "Issue B")
  store.add("a.lua", 5, "suggestion", "Suggestion A")

  local md = export.generate_markdown()
  expect_match(md, "1%. %*%*%[NOTE%]%*%*")
  expect_match(md, "2%. %*%*%[SUGGESTION%]%*%*")
  expect_match(md, "3%. %*%*%[ISSUE%]%*%*")
end

T["generate_markdown"]["uses tilde notation for old-side comments"] = function()
  store.add("src/main.lua", 10, "issue", "Removed bug", nil, "old")

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:~10")
end

T["generate_markdown"]["uses tilde on both ends for old-side range"] = function()
  store.add("src/main.lua", 10, "issue", "Old range", 15, "old")

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:~10%-~15")
end

T["generate_markdown"]["uses normal notation for new-side comments"] = function()
  store.add("src/main.lua", 10, "issue", "New side", nil, "new")

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:10")
  expect_no_match(md, "~10")
end

return T
