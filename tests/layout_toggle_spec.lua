local store = require("review.store")
local marks = require("review.marks")
local config = require("review.config")

describe("layout toggle comment persistence", function()
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
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  describe("comments survive buffer recreation", function()
    it("re-renders comments on a new buffer for the same file", function()
      local ns_id = vim.api.nvim_create_namespace("review")

      -- Add comments to the store (simulates comments added before layout toggle)
      store.add("test.lua", 3, "issue", "Fix this")
      store.add("test.lua", 5, "note", "Nice work")

      -- Render on original buffer
      marks.render_for_buffer(bufnr, "new", "test.lua")
      local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(2, #extmarks_before)

      -- Simulate layout toggle: create a brand new buffer (codediff recreates buffers)
      local new_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {
        "local M = {}",
        "",
        "function M.hello()",
        "  print('hello')",
        "end",
        "",
        "return M",
      })

      -- Old buffer's extmarks are gone from the new buffer's perspective
      local new_extmarks_before = vim.api.nvim_buf_get_extmarks(new_buf, ns_id, 0, -1, {})
      assert.equals(0, #new_extmarks_before)

      -- Re-render on new buffer (what on_session_created does after CodeDiffOpen)
      marks.render_for_buffer(new_buf, "new", "test.lua")

      -- Comments should appear on the new buffer
      local new_extmarks_after = vim.api.nvim_buf_get_extmarks(new_buf, ns_id, 0, -1, {})
      assert.equals(2, #new_extmarks_after)

      vim.api.nvim_buf_delete(new_buf, { force = true })
    end)

    it("re-renders file comments on a new buffer", function()
      local ns_id = vim.api.nvim_create_namespace("review")

      store.add("test.lua", 0, "note", "File-level comment")
      marks.render_for_buffer(bufnr, "new", "test.lua")

      local extmarks_before = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
      assert.equals(1, #extmarks_before)

      -- New buffer after layout toggle
      local new_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {
        "local M = {}",
        "return M",
      })

      marks.render_for_buffer(new_buf, "new", "test.lua")

      local new_extmarks = vim.api.nvim_buf_get_extmarks(new_buf, ns_id, 0, -1, { details = true })
      assert.equals(1, #new_extmarks)
      assert.equals(true, new_extmarks[1][4].virt_lines_above)

      vim.api.nvim_buf_delete(new_buf, { force = true })
    end)

    it("re-renders alignment padding on new buffers", function()
      local ns_padding = vim.api.nvim_create_namespace("review_padding")

      store.add("test.lua", 3, "issue", "Only on new side", nil, "new")

      local orig_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, {
        "line1", "line2", "line3", "line4", "line5",
      })
      local mod_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, {
        "line1", "line2", "line3", "line4", "line5",
      })

      marks.render_for_buffer(orig_buf, "old", "test.lua")
      marks.render_for_buffer(mod_buf, "new", "test.lua")
      marks.align_buffers(orig_buf, mod_buf, "test.lua")

      -- Padding should exist on orig_buf
      local padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
      assert.equals(1, #padding)

      -- Simulate layout toggle: new buffers
      local new_orig = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(new_orig, 0, -1, false, {
        "line1", "line2", "line3", "line4", "line5",
      })
      local new_mod = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(new_mod, 0, -1, false, {
        "line1", "line2", "line3", "line4", "line5",
      })

      -- Re-render and re-align (what refresh() does)
      marks.render_for_buffer(new_orig, "old", "test.lua")
      marks.render_for_buffer(new_mod, "new", "test.lua")
      marks.align_buffers(new_orig, new_mod, "test.lua")

      -- Padding should exist on the new orig buffer
      local new_padding = vim.api.nvim_buf_get_extmarks(new_orig, ns_padding, 0, -1, {})
      assert.equals(1, #new_padding)

      vim.api.nvim_buf_delete(orig_buf, { force = true })
      vim.api.nvim_buf_delete(mod_buf, { force = true })
      vim.api.nvim_buf_delete(new_orig, { force = true })
      vim.api.nvim_buf_delete(new_mod, { force = true })
    end)
  end)

  describe("CodeDiffOpen autocmd", function()
    it("autocmd is registered after setup", function()
      -- Run setup to register autocmds
      local review = require("review")
      review.setup()

      local autocmds = vim.api.nvim_get_autocmds({
        group = "review",
        event = "User",
        pattern = "CodeDiffOpen",
      })
      assert.is_true(#autocmds > 0)
    end)
  end)
end)
