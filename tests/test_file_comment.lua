local H = dofile("tests/helpers.lua")
local eq, neq, expect_match, expect_no_match = H.eq, H.neq, H.expect_match, H.expect_no_match

local store = require("review.store")
local marks = require("review.marks")
local export = require("review.export")
local config = require("review.config")

local bufnr
local ns_id = vim.api.nvim_create_namespace("review")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "local M = {}",
        "",
        "function M.hello()",
        "  print('hello')",
        "end",
        "",
        "return M",
      })
      vim.api.nvim_buf_set_name(bufnr, "file_comment_test.lua")
      vim.api.nvim_set_current_buf(bufnr)
    end,
    post_case = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
  },
})

T["store"] = MiniTest.new_set()

T["store"]["adds a file comment with line 0"] = function()
  local comment = store.add("file.lua", 0, "note", "Needs refactoring")
  eq(comment.line, 0)
  eq(comment.type, "note")
  eq(comment.text, "Needs refactoring")
end

T["store"]["get_file_comment finds line-0 comment"] = function()
  store.add("file.lua", 0, "note", "File-level note")
  local comment = store.get_file_comment("file.lua")
  neq(comment, nil)
  eq(comment.text, "File-level note")
end

T["store"]["get_file_comment returns nil when none exists"] = function()
  store.add("file.lua", 5, "note", "Line comment")
  eq(store.get_file_comment("file.lua"), nil)
end

T["store"]["get_file_comment returns nil for empty file"] = function()
  eq(store.get_file_comment("file.lua"), nil)
end

T["store"]["get_at_line does NOT match line-0 comment at line 1"] = function()
  store.add("file.lua", 0, "note", "File-level")
  eq(store.get_at_line("file.lua", 1), nil)
end

T["store"]["get_overlapping does NOT match line-0 comment"] = function()
  store.add("file.lua", 0, "note", "File-level")
  eq(store.get_overlapping("file.lua", 1, 5), nil)
end

T["store"]["get_all sorts file comments before line comments"] = function()
  store.add("file.lua", 5, "note", "Line 5")
  store.add("file.lua", 0, "note", "File-level")

  local all = store.get_all()
  eq(#all, 2)
  eq(all[1].text, "File-level")
  eq(all[2].text, "Line 5")
end

T["store"]["file and line comments coexist"] = function()
  store.add("file.lua", 0, "note", "File comment")
  store.add("file.lua", 10, "issue", "Line comment")

  eq(#store.get_for_file("file.lua"), 2)
  neq(store.get_file_comment("file.lua"), nil)
  neq(store.get_at_line("file.lua", 10), nil)
end

T["marks rendering"] = MiniTest.new_set()

T["marks rendering"]["renders file comment at row 0 with virt_lines_above"] = function()
  store.add("file_comment_test.lua", 0, "note", "Nice module")
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks, 1)

  local details = extmarks[1][4]
  eq(details.virt_lines_above, true)
  neq(details.virt_lines, nil)
  eq(#details.virt_lines > 0, true)
  eq(extmarks[1][2], 0)
end

T["marks rendering"]["renders both file and line comments"] = function()
  store.add("file_comment_test.lua", 0, "note", "File comment")
  store.add("file_comment_test.lua", 3, "issue", "Line comment")
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks, 2)
end

T["marks rendering"]["file comment has sign icon"] = function()
  store.add("file_comment_test.lua", 0, "issue", "Fix everything")
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  neq(extmarks[1][4].sign_text, nil)
end

T["marks rendering"]["file comment has no line highlight"] = function()
  store.add("file_comment_test.lua", 0, "issue", "Fix everything")
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(extmarks[1][4].line_hl_group, nil)
end

T["export"] = MiniTest.new_set()

T["export"]["formats file-level comment without line number"] = function()
  store.add("src/main.lua", 0, "note", "Good module structure")

  local md = export.generate_markdown()
  expect_match(md, "`src/main.lua`", true)
  expect_no_match(md, "src/main.lua:0", true)
end

T["export"]["mixes file-level and line comments correctly"] = function()
  store.add("src/main.lua", 0, "note", "File note")
  store.add("src/main.lua", 10, "issue", "Line issue")

  local md = export.generate_markdown()
  expect_match(md, "`src/main.lua`", true)
  expect_match(md, "src/main.lua:10")
end

T["side awareness"] = MiniTest.new_set()

T["side awareness"]["file comment renders on both sides via get_for_file"] = function()
  store.add("file_comment_test.lua", 0, "note", "File comment")
  store.add("file_comment_test.lua", 5, "issue", "New side", nil, "new")

  local old_comments = store.get_for_file("file_comment_test.lua", "old")
  local new_comments = store.get_for_file("file_comment_test.lua", "new")

  -- file comment (line 0) appears in both
  eq(#old_comments, 1)
  eq(old_comments[1].line, 0)

  eq(#new_comments, 2)
end

T["side awareness"]["renders file comment marks on both old and new buffers"] = function()
  store.add("file_comment_test.lua", 0, "note", "File note")

  -- Render with "old" side
  marks.render_for_buffer(bufnr, "old")
  local extmarks_old = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks_old, 1)

  -- Clear and render with "new" side
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  marks.render_for_buffer(bufnr, "new")
  local extmarks_new = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks_new, 1)
end

T["side awareness"]["line comment only renders on matching side"] = function()
  store.add("file_comment_test.lua", 3, "issue", "New only", nil, "new")

  marks.render_for_buffer(bufnr, "old")
  local extmarks_old = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks_old, 0)

  marks.render_for_buffer(bufnr, "new")
  local extmarks_new = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(#extmarks_new, 1)
end

return T
