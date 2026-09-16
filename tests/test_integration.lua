local H = dofile("tests/helpers.lua")
local eq, neq, expect_match = H.eq, H.neq, H.expect_match

local store = require("review.store")
local marks = require("review.marks")
local config = require("review.config")

local bufnr

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()

      -- Create a test buffer with content
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "local M = {}",
        "",
        "function M.hello()",
        "  print('hello')",
        "end",
        "",
        "function M.world()",
        "  print('world')",
        "end",
        "",
        "return M",
      })
      vim.api.nvim_buf_set_name(bufnr, "test_file.lua")
      vim.api.nvim_set_current_buf(bufnr)
    end,
    post_case = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
  },
})

T["comments and marks"] = MiniTest.new_set()

T["comments and marks"]["adds comment and renders extmark on buffer"] = function()
  -- Add a comment
  store.add("test_file.lua", 3, "issue", "This function needs error handling")

  -- Render marks
  marks.render_for_buffer(bufnr)

  -- Check extmarks were created
  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
  -- Line 3 is index 2 (0-based)
  eq(2, extmarks[1][2])
end

T["comments and marks"]["renders multiple comments on different lines"] = function()
  store.add("test_file.lua", 3, "issue", "Issue here")
  store.add("test_file.lua", 7, "suggestion", "Consider refactoring")
  store.add("test_file.lua", 4, "praise", "Nice and clean")

  marks.render_for_buffer(bufnr)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(3, #extmarks)
end

T["comments and marks"]["clears marks when comments are cleared"] = function()
  store.add("test_file.lua", 3, "issue", "Issue here")
  marks.render_for_buffer(bufnr)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
  eq(1, #extmarks_before)

  -- Clear all
  store.clear()
  marks.clear_all()

  local extmarks_after = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
  eq(0, #extmarks_after)
end

T["comments and marks"]["extmarks include virtual text with comment type"] = function()
  store.add("test_file.lua", 3, "issue", "Fix this bug")

  marks.render_for_buffer(bufnr)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
  local details = extmarks[1][4]
  -- Check virtual lines exist
  neq(details.virt_lines, nil)
  eq(#details.virt_lines > 0, true)
end

T["comments and marks"]["extmarks include sign in gutter"] = function()
  store.add("test_file.lua", 3, "note", "A note")

  marks.render_for_buffer(bufnr)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  local details = extmarks[1][4]
  neq(details.sign_text, nil)
end

T["comment types"] = MiniTest.new_set()

T["comment types"]["each comment type has correct highlight group"] = function()
  local cfg = config.get()

  for type_name, type_info in pairs(cfg.comment_types) do
    store.add("test_file.lua", 3, type_name, "Test " .. type_name)
    marks.render_for_buffer(bufnr)

    local ns_id = vim.api.nvim_create_namespace("review")
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

    local details = extmarks[1][4]
    eq(type_info.hl, details.sign_hl_group)

    store.clear()
    marks.clear_all()
  end
end

T["export integration"] = MiniTest.new_set()

T["export integration"]["exports comments from buffer to markdown"] = function()
  store.add("test_file.lua", 3, "issue", "Missing error handling")
  store.add("test_file.lua", 7, "suggestion", "Use local variable")

  local export = require("review.export")
  local md = export.generate_markdown()

  expect_match(md, "test_file.lua:3")
  expect_match(md, "test_file.lua:7")
  expect_match(md, "%[ISSUE%]")
  expect_match(md, "%[SUGGESTION%]")
  expect_match(md, "Missing error handling")
  expect_match(md, "Use local variable")
end

return T
