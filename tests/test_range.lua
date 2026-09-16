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
        "  print('world')",
        "end",
        "",
        "function M.goodbye()",
        "  print('goodbye')",
        "end",
        "",
        "return M",
      })
      vim.api.nvim_buf_set_name(bufnr, "range_test.lua")
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

T["store"]["add with line_end"] = MiniTest.new_set()

T["store"]["add with line_end"]["stores line_end when different from line"] = function()
  local comment = store.add("file.lua", 3, "issue", "Fix range", 6)
  eq(3, comment.line)
  eq(6, comment.line_end)
end

T["store"]["add with line_end"]["does not store line_end when same as line"] = function()
  local comment = store.add("file.lua", 3, "issue", "Single line", 3)
  eq(comment.line_end, nil)
end

T["store"]["add with line_end"]["does not store line_end when nil"] = function()
  local comment = store.add("file.lua", 3, "issue", "No range")
  eq(comment.line_end, nil)
end

T["store"]["get_at_line with ranges"] = MiniTest.new_set()

T["store"]["get_at_line with ranges"]["finds comment when cursor is at range start"] = function()
  store.add("file.lua", 3, "issue", "Range comment", 6)
  local comment = store.get_at_line("file.lua", 3)
  neq(comment, nil)
  eq("Range comment", comment.text)
end

T["store"]["get_at_line with ranges"]["finds comment when cursor is at range end"] = function()
  store.add("file.lua", 3, "issue", "Range comment", 6)
  local comment = store.get_at_line("file.lua", 6)
  neq(comment, nil)
  eq("Range comment", comment.text)
end

T["store"]["get_at_line with ranges"]["finds comment when cursor is in range middle"] = function()
  store.add("file.lua", 3, "issue", "Range comment", 6)
  local comment = store.get_at_line("file.lua", 4)
  neq(comment, nil)
  eq("Range comment", comment.text)
end

T["store"]["get_at_line with ranges"]["returns nil when cursor is outside range"] = function()
  store.add("file.lua", 3, "issue", "Range comment", 6)
  eq(store.get_at_line("file.lua", 2), nil)
  eq(store.get_at_line("file.lua", 7), nil)
end

T["store"]["get_at_line with ranges"]["still works for single-line comments without line_end"] = function()
  store.add("file.lua", 5, "note", "Single")
  neq(store.get_at_line("file.lua", 5), nil)
  eq(store.get_at_line("file.lua", 6), nil)
end

T["store"]["get_overlapping"] = MiniTest.new_set()

T["store"]["get_overlapping"]["detects full overlap"] = function()
  store.add("file.lua", 3, "issue", "Existing", 6)
  local overlap = store.get_overlapping("file.lua", 3, 6)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["detects partial overlap at start"] = function()
  store.add("file.lua", 3, "issue", "Existing", 6)
  local overlap = store.get_overlapping("file.lua", 1, 4)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["detects partial overlap at end"] = function()
  store.add("file.lua", 3, "issue", "Existing", 6)
  local overlap = store.get_overlapping("file.lua", 5, 8)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["detects new range containing existing"] = function()
  store.add("file.lua", 4, "issue", "Existing", 5)
  local overlap = store.get_overlapping("file.lua", 3, 6)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["detects existing range containing new"] = function()
  store.add("file.lua", 3, "issue", "Existing", 6)
  local overlap = store.get_overlapping("file.lua", 4, 5)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["returns nil for non-overlapping ranges"] = function()
  store.add("file.lua", 3, "issue", "Existing", 6)
  eq(store.get_overlapping("file.lua", 7, 10), nil)
  eq(store.get_overlapping("file.lua", 1, 2), nil)
end

T["store"]["get_overlapping"]["detects overlap with single-line comment"] = function()
  store.add("file.lua", 5, "issue", "Single")
  local overlap = store.get_overlapping("file.lua", 3, 7)
  neq(overlap, nil)
end

T["store"]["get_overlapping"]["returns nil when single-line comment not in range"] = function()
  store.add("file.lua", 5, "issue", "Single")
  eq(store.get_overlapping("file.lua", 6, 10), nil)
end

T["store"]["get_overlapping"]["returns nil for different file"] = function()
  store.add("a.lua", 3, "issue", "Comment", 6)
  eq(store.get_overlapping("b.lua", 3, 6), nil)
end

T["store"]["get_overlapping"]["detects adjacent ranges (touching at boundary)"] = function()
  store.add("file.lua", 3, "issue", "First", 5)
  local overlap = store.get_overlapping("file.lua", 5, 7)
  neq(overlap, nil)
end

T["marks rendering"] = MiniTest.new_set()

T["marks rendering"]["renders range comment with extmarks on all lines"] = function()
  store.add("range_test.lua", 3, "issue", "Needs refactor", 6)
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  -- Start line (3->idx 2) + middle lines (4->idx 3, 5->idx 4) + end line (6->idx 5) = 4 extmarks
  eq(4, #extmarks)
end

T["marks rendering"]["places sign only on start line of range"] = function()
  store.add("range_test.lua", 3, "issue", "Range", 6)
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  local signs_found = 0
  for _, ext in ipairs(extmarks) do
    if ext[4].sign_text then
      signs_found = signs_found + 1
    end
  end
  eq(1, signs_found)

  -- First extmark (start line) should have the sign
  neq(extmarks[1][4].sign_text, nil)
end

T["marks rendering"]["places virt_lines only on last line of range"] = function()
  store.add("range_test.lua", 3, "issue", "Range", 6)
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  local virt_found = 0
  local last_with_virt = nil
  for _, ext in ipairs(extmarks) do
    if ext[4].virt_lines and #ext[4].virt_lines > 0 then
      virt_found = virt_found + 1
      last_with_virt = ext[2]
    end
  end
  eq(1, virt_found)
  -- Should be on line 6 (0-indexed = 5)
  eq(5, last_with_virt)
end

T["marks rendering"]["applies line_hl to all lines in range"] = function()
  store.add("range_test.lua", 3, "issue", "Range", 6)
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  for _, ext in ipairs(extmarks) do
    neq(ext[4].line_hl_group, nil)
  end
end

T["marks rendering"]["single-line comment still renders as single extmark"] = function()
  store.add("range_test.lua", 3, "issue", "Single")
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
  eq(1, #extmarks)

  local details = extmarks[1][4]
  neq(details.sign_text, nil)
  neq(details.virt_lines, nil)
  eq(#details.virt_lines > 0, true)
end

T["marks rendering"]["renders 2-line range correctly (no middle lines)"] = function()
  store.add("range_test.lua", 3, "note", "Two lines", 4)
  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  -- Just start + end = 2 extmarks (no middle)
  eq(2, #extmarks)

  -- First: sign, no virt_lines
  neq(extmarks[1][4].sign_text, nil)
  eq(extmarks[1][4].virt_lines, nil)

  -- Second: virt_lines, no sign
  eq(extmarks[2][4].sign_text, nil)
  neq(extmarks[2][4].virt_lines, nil)
end

T["marks rendering"]["can render both single and range comments in same file"] = function()
  store.add("range_test.lua", 1, "note", "Single comment")
  store.add("range_test.lua", 3, "issue", "Range comment", 5)

  marks.render_for_buffer(bufnr)

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  -- Single: 1 extmark. Range 3-5: start + middle(4) + end = 3 extmarks. Total: 4
  eq(4, #extmarks)
end

T["export"] = MiniTest.new_set()

T["export"]["formats range comments with line range"] = function()
  store.add("src/main.lua", 10, "issue", "Refactor this block", 15)

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:10%-15")
  expect_match(md, "%[ISSUE%]")
end

T["export"]["keeps single-line format for non-range comments"] = function()
  store.add("src/main.lua", 10, "note", "Simple note")

  local md = export.generate_markdown()
  expect_match(md, "src/main.lua:10`")
  -- Should NOT have a dash after the line number
  expect_no_match(md, "src/main.lua:10%-")
end

T["export"]["mixes range and single-line in output"] = function()
  store.add("a.lua", 5, "note", "Single")
  store.add("b.lua", 10, "issue", "Range", 20)

  local md = export.generate_markdown()
  expect_match(md, "a.lua:5`")
  expect_match(md, "b.lua:10%-20")
end

return T
