local store = require("review.store")
local marks = require("review.marks")
local export = require("review.export")
local config = require("review.config")

describe("line-range comments", function()
  local bufnr

  before_each(function()
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
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("store", function()
    describe("add with line_end", function()
      it("stores line_end when different from line", function()
        local comment = store.add("file.lua", 3, "issue", "Fix range", 6)
        assert.equals(3, comment.line)
        assert.equals(6, comment.line_end)
      end)

      it("does not store line_end when same as line", function()
        local comment = store.add("file.lua", 3, "issue", "Single line", 3)
        assert.is_nil(comment.line_end)
      end)

      it("does not store line_end when nil", function()
        local comment = store.add("file.lua", 3, "issue", "No range")
        assert.is_nil(comment.line_end)
      end)
    end)

    describe("get_at_line with ranges", function()
      it("finds comment when cursor is at range start", function()
        store.add("file.lua", 3, "issue", "Range comment", 6)
        local comment = store.get_at_line("file.lua", 3)
        assert.is_not_nil(comment)
        assert.equals("Range comment", comment.text)
      end)

      it("finds comment when cursor is at range end", function()
        store.add("file.lua", 3, "issue", "Range comment", 6)
        local comment = store.get_at_line("file.lua", 6)
        assert.is_not_nil(comment)
        assert.equals("Range comment", comment.text)
      end)

      it("finds comment when cursor is in range middle", function()
        store.add("file.lua", 3, "issue", "Range comment", 6)
        local comment = store.get_at_line("file.lua", 4)
        assert.is_not_nil(comment)
        assert.equals("Range comment", comment.text)
      end)

      it("returns nil when cursor is outside range", function()
        store.add("file.lua", 3, "issue", "Range comment", 6)
        assert.is_nil(store.get_at_line("file.lua", 2))
        assert.is_nil(store.get_at_line("file.lua", 7))
      end)

      it("still works for single-line comments without line_end", function()
        store.add("file.lua", 5, "note", "Single")
        assert.is_not_nil(store.get_at_line("file.lua", 5))
        assert.is_nil(store.get_at_line("file.lua", 6))
      end)
    end)

    describe("get_overlapping", function()
      it("detects full overlap", function()
        store.add("file.lua", 3, "issue", "Existing", 6)
        local overlap = store.get_overlapping("file.lua", 3, 6)
        assert.is_not_nil(overlap)
      end)

      it("detects partial overlap at start", function()
        store.add("file.lua", 3, "issue", "Existing", 6)
        local overlap = store.get_overlapping("file.lua", 1, 4)
        assert.is_not_nil(overlap)
      end)

      it("detects partial overlap at end", function()
        store.add("file.lua", 3, "issue", "Existing", 6)
        local overlap = store.get_overlapping("file.lua", 5, 8)
        assert.is_not_nil(overlap)
      end)

      it("detects new range containing existing", function()
        store.add("file.lua", 4, "issue", "Existing", 5)
        local overlap = store.get_overlapping("file.lua", 3, 6)
        assert.is_not_nil(overlap)
      end)

      it("detects existing range containing new", function()
        store.add("file.lua", 3, "issue", "Existing", 6)
        local overlap = store.get_overlapping("file.lua", 4, 5)
        assert.is_not_nil(overlap)
      end)

      it("returns nil for non-overlapping ranges", function()
        store.add("file.lua", 3, "issue", "Existing", 6)
        assert.is_nil(store.get_overlapping("file.lua", 7, 10))
        assert.is_nil(store.get_overlapping("file.lua", 1, 2))
      end)

      it("detects overlap with single-line comment", function()
        store.add("file.lua", 5, "issue", "Single")
        local overlap = store.get_overlapping("file.lua", 3, 7)
        assert.is_not_nil(overlap)
      end)

      it("returns nil when single-line comment not in range", function()
        store.add("file.lua", 5, "issue", "Single")
        assert.is_nil(store.get_overlapping("file.lua", 6, 10))
      end)

      it("returns nil for different file", function()
        store.add("a.lua", 3, "issue", "Comment", 6)
        assert.is_nil(store.get_overlapping("b.lua", 3, 6))
      end)

      it("detects adjacent ranges (touching at boundary)", function()
        store.add("file.lua", 3, "issue", "First", 5)
        local overlap = store.get_overlapping("file.lua", 5, 7)
        assert.is_not_nil(overlap)
      end)
    end)
  end)

  describe("marks rendering", function()
    local ns_id = vim.api.nvim_create_namespace("review")

    it("renders range comment with extmarks on all lines", function()
      store.add("range_test.lua", 3, "issue", "Needs refactor", 6)
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

      -- Start line (3->idx 2) + middle lines (4->idx 3, 5->idx 4) + end line (6->idx 5) = 4 extmarks
      assert.equals(4, #extmarks)
    end)

    it("places sign only on start line of range", function()
      store.add("range_test.lua", 3, "issue", "Range", 6)
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

      local signs_found = 0
      for _, ext in ipairs(extmarks) do
        if ext[4].sign_text then
          signs_found = signs_found + 1
        end
      end
      assert.equals(1, signs_found)

      -- First extmark (start line) should have the sign
      assert.is_not_nil(extmarks[1][4].sign_text)
    end)

    it("places virt_lines only on last line of range", function()
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
      assert.equals(1, virt_found)
      -- Should be on line 6 (0-indexed = 5)
      assert.equals(5, last_with_virt)
    end)

    it("applies line_hl to all lines in range", function()
      store.add("range_test.lua", 3, "issue", "Range", 6)
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

      for _, ext in ipairs(extmarks) do
        assert.is_not_nil(ext[4].line_hl_group)
      end
    end)

    it("single-line comment still renders as single extmark", function()
      store.add("range_test.lua", 3, "issue", "Single")
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(1, #extmarks)

      local details = extmarks[1][4]
      assert.is_not_nil(details.sign_text)
      assert.is_not_nil(details.virt_lines)
      assert.is_true(#details.virt_lines > 0)
    end)

    it("renders 2-line range correctly (no middle lines)", function()
      store.add("range_test.lua", 3, "note", "Two lines", 4)
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

      -- Just start + end = 2 extmarks (no middle)
      assert.equals(2, #extmarks)

      -- First: sign, no virt_lines
      assert.is_not_nil(extmarks[1][4].sign_text)
      assert.is_nil(extmarks[1][4].virt_lines)

      -- Second: virt_lines, no sign
      assert.is_nil(extmarks[2][4].sign_text)
      assert.is_not_nil(extmarks[2][4].virt_lines)
    end)

    it("can render both single and range comments in same file", function()
      store.add("range_test.lua", 1, "note", "Single comment")
      store.add("range_test.lua", 3, "issue", "Range comment", 5)

      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

      -- Single: 1 extmark. Range 3-5: start + middle(4) + end = 3 extmarks. Total: 4
      assert.equals(4, #extmarks)
    end)
  end)

  describe("export", function()
    it("formats range comments with line range", function()
      store.add("src/main.lua", 10, "issue", "Refactor this block", 15)

      local md = export.generate_markdown()
      assert.matches("src/main.lua:10%-15", md)
      assert.matches("%[ISSUE%]", md)
    end)

    it("keeps single-line format for non-range comments", function()
      store.add("src/main.lua", 10, "note", "Simple note")

      local md = export.generate_markdown()
      assert.matches("src/main.lua:10`", md)
      -- Should NOT have a dash after the line number
      assert.not_matches("src/main.lua:10%-", md)
    end)

    it("mixes range and single-line in output", function()
      store.add("a.lua", 5, "note", "Single")
      store.add("b.lua", 10, "issue", "Range", 20)

      local md = export.generate_markdown()
      assert.matches("a.lua:5`", md)
      assert.matches("b.lua:10%-20", md)
    end)
  end)
end)
