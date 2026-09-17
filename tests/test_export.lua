local H = dofile("tests/helpers.lua")
local expect_match, expect_no_match = H.expect_match, H.expect_no_match
local eq = H.eq

local store = require("review.store")
local config = require("review.config")
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

T["deliver"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()
      vim.fn.setreg("+", "untouched")
    end,
    post_case = function()
      config.setup()
    end,
  },
})

T["deliver"]["returns nothing when there are no comments"] = function()
  local markdown, count = export.deliver()
  eq(markdown, nil)
  eq(count, 0)
  eq(vim.fn.getreg("+"), "untouched")
end

T["deliver"]["copies to the clipboard and calls on_export with markdown and comments"] = function()
  local got
  config.get().export.on_export = function(markdown, comments)
    got = { markdown = markdown, comments = comments }
  end
  store.add("src/main.lua", 10, "issue", "Fix this bug")

  local markdown, count = export.deliver()
  eq(count, 1)
  eq(vim.fn.getreg("+"), markdown)
  eq(got.markdown, markdown)
  eq(#got.comments, 1)
  eq(got.comments[1].file, "src/main.lua")
  eq(got.comments[1].line, 10)
end

T["deliver"]["leaves the clipboard alone when export.clipboard is off"] = function()
  local called = false
  config.get().export.clipboard = false
  config.get().export.on_export = function() called = true end
  store.add("src/main.lua", 10, "issue", "Fix this bug")

  local markdown = export.deliver()
  expect_match(markdown, "Fix this bug")
  eq(vim.fn.getreg("+"), "untouched")
  eq(called, true)
  eq(export.delivered_message(1), "Exported 1 comment(s) to on_export")
end

T["deliver"]["survives a failing on_export"] = function()
  config.get().export.on_export = function() error("boom") end
  store.add("src/main.lua", 10, "issue", "Fix this bug")

  local markdown, count = export.deliver()
  eq(count, 1)
  eq(vim.fn.getreg("+"), markdown)
end

return T
