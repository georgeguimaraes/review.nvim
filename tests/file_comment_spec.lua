local store = require("review.store")
local marks = require("review.marks")
local export = require("review.export")
local config = require("review.config")

describe("file-level comments", function()
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
      "end",
      "",
      "return M",
    })
    vim.api.nvim_buf_set_name(bufnr, "file_comment_test.lua")
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("store", function()
    it("adds a file comment with line 0", function()
      local comment = store.add("file.lua", 0, "note", "Needs refactoring")
      assert.equals(0, comment.line)
      assert.equals("note", comment.type)
      assert.equals("Needs refactoring", comment.text)
    end)

    it("get_file_comment finds line-0 comment", function()
      store.add("file.lua", 0, "note", "File-level note")
      local comment = store.get_file_comment("file.lua")
      assert.is_not_nil(comment)
      assert.equals("File-level note", comment.text)
    end)

    it("get_file_comment returns nil when none exists", function()
      store.add("file.lua", 5, "note", "Line comment")
      assert.is_nil(store.get_file_comment("file.lua"))
    end)

    it("get_file_comment returns nil for empty file", function()
      assert.is_nil(store.get_file_comment("file.lua"))
    end)

    it("get_at_line does NOT match line-0 comment at line 1", function()
      store.add("file.lua", 0, "note", "File-level")
      assert.is_nil(store.get_at_line("file.lua", 1))
    end)

    it("get_overlapping does NOT match line-0 comment", function()
      store.add("file.lua", 0, "note", "File-level")
      assert.is_nil(store.get_overlapping("file.lua", 1, 5))
    end)

    it("get_all sorts file comments before line comments", function()
      store.add("file.lua", 5, "note", "Line 5")
      store.add("file.lua", 0, "note", "File-level")

      local all = store.get_all()
      assert.equals(2, #all)
      assert.equals("File-level", all[1].text)
      assert.equals("Line 5", all[2].text)
    end)

    it("file and line comments coexist", function()
      store.add("file.lua", 0, "note", "File comment")
      store.add("file.lua", 10, "issue", "Line comment")

      assert.equals(2, #store.get_for_file("file.lua"))
      assert.is_not_nil(store.get_file_comment("file.lua"))
      assert.is_not_nil(store.get_at_line("file.lua", 10))
    end)
  end)

  describe("marks rendering", function()
    local ns_id = vim.api.nvim_create_namespace("review")

    it("renders file comment at row 0 with virt_lines_above", function()
      store.add("file_comment_test.lua", 0, "note", "Nice module")
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(1, #extmarks)

      local details = extmarks[1][4]
      assert.equals(true, details.virt_lines_above)
      assert.is_not_nil(details.virt_lines)
      assert.is_true(#details.virt_lines > 0)
      assert.equals(0, extmarks[1][2])
    end)

    it("renders both file and line comments", function()
      store.add("file_comment_test.lua", 0, "note", "File comment")
      store.add("file_comment_test.lua", 3, "issue", "Line comment")
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(2, #extmarks)
    end)

    it("file comment has sign icon", function()
      store.add("file_comment_test.lua", 0, "issue", "Fix everything")
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_not_nil(extmarks[1][4].sign_text)
    end)

    it("file comment has no line highlight", function()
      store.add("file_comment_test.lua", 0, "issue", "Fix everything")
      marks.render_for_buffer(bufnr)

      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.is_nil(extmarks[1][4].line_hl_group)
    end)
  end)

  describe("export", function()
    it("formats file-level comment without line number", function()
      store.add("src/main.lua", 0, "note", "Good module structure")

      local md = export.generate_markdown()
      assert.matches("`src/main.lua`", md, 1, true)
      assert.not_matches("src/main.lua:0", md, 1, true)
    end)

    it("mixes file-level and line comments correctly", function()
      store.add("src/main.lua", 0, "note", "File note")
      store.add("src/main.lua", 10, "issue", "Line issue")

      local md = export.generate_markdown()
      assert.matches("`src/main.lua`", md, 1, true)
      assert.matches("src/main.lua:10", md)
    end)
  end)

  describe("side awareness", function()
    it("file comment renders on both sides via get_for_file", function()
      store.add("file_comment_test.lua", 0, "note", "File comment")
      store.add("file_comment_test.lua", 5, "issue", "New side", nil, "new")

      local old_comments = store.get_for_file("file_comment_test.lua", "old")
      local new_comments = store.get_for_file("file_comment_test.lua", "new")

      -- file comment (line 0) appears in both
      assert.equals(1, #old_comments)
      assert.equals(0, old_comments[1].line)

      assert.equals(2, #new_comments)
    end)

    it("renders file comment marks on both old and new buffers", function()
      local ns_id = vim.api.nvim_create_namespace("review")
      store.add("file_comment_test.lua", 0, "note", "File note")

      -- Render with "old" side
      marks.render_for_buffer(bufnr, "old")
      local extmarks_old = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(1, #extmarks_old)

      -- Clear and render with "new" side
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      marks.render_for_buffer(bufnr, "new")
      local extmarks_new = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(1, #extmarks_new)
    end)

    it("line comment only renders on matching side", function()
      local ns_id = vim.api.nvim_create_namespace("review")
      store.add("file_comment_test.lua", 3, "issue", "New only", nil, "new")

      marks.render_for_buffer(bufnr, "old")
      local extmarks_old = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(0, #extmarks_old)

      marks.render_for_buffer(bufnr, "new")
      local extmarks_new = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
      assert.equals(1, #extmarks_new)
    end)
  end)
end)
