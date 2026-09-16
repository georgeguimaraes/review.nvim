local H = dofile("tests/helpers.lua")
local eq, neq = H.eq, H.neq

local store = require("review.store")
local marks = require("review.marks")
local config = require("review.config")

local orig_buf, mod_buf
local ns_padding

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()
      ns_padding = vim.api.nvim_create_namespace("review_padding")

      local lines = {
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
      }

      orig_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, lines)

      mod_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, lines)
    end,
    post_case = function()
      for _, buf in ipairs({ orig_buf, mod_buf }) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["align_buffers"] = MiniTest.new_set()

T["align_buffers"]["adds padding on old side when comment exists only on new side"] = function()
  store.add("test.lua", 3, "issue", "Fix this", nil, "new")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local padding_marks = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, { details = true })
  eq(1, #padding_marks)

  -- Padding should have virt_lines matching the comment box height (1 line text = 3 total)
  local details = padding_marks[1][4]
  neq(details.virt_lines, nil)
  eq(3, #details.virt_lines)
end

T["align_buffers"]["adds padding on new side when comment exists only on old side"] = function()
  store.add("test.lua", 3, "note", "Old note", nil, "old")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local padding_marks = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, { details = true })
  eq(1, #padding_marks)

  local details = padding_marks[1][4]
  eq(3, #details.virt_lines)
end

T["align_buffers"]["adds no padding when no comments exist"] = function()
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local orig_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  local mod_padding = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, {})
  eq(0, #orig_padding)
  eq(0, #mod_padding)
end

T["align_buffers"]["adds no padding when both sides have same-height comments at same line"] = function()
  store.add("test.lua", 3, "issue", "Old comment", nil, "old")
  store.add("test.lua", 3, "note", "New comment", nil, "new")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local orig_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  local mod_padding = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, {})
  eq(0, #orig_padding)
  eq(0, #mod_padding)
end

T["align_buffers"]["pads the shorter side when comments have different heights"] = function()
  -- Multi-line comment on new side (3 text lines = 5 box lines)
  store.add("test.lua", 3, "issue", "Line one\nLine two\nLine three", nil, "new")
  -- Single-line comment on old side (1 text line = 3 box lines)
  store.add("test.lua", 3, "note", "Short", nil, "old")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  -- Old side should get 2 lines of padding (5 - 3 = 2)
  local orig_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, { details = true })
  eq(1, #orig_padding)
  eq(2, #orig_padding[1][4].virt_lines)

  -- New side should have no padding
  local mod_padding = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, {})
  eq(0, #mod_padding)
end

T["align_buffers"]["handles comments on different lines independently"] = function()
  store.add("test.lua", 3, "issue", "On new at 3", nil, "new")
  store.add("test.lua", 7, "note", "On old at 7", nil, "old")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  -- Old side gets padding at line 3 (for new-side comment)
  local orig_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  eq(1, #orig_padding)

  -- New side gets padding at line 7 (for old-side comment)
  local mod_padding = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, {})
  eq(1, #mod_padding)
end

T["align_buffers"]["clears old padding before recalculating"] = function()
  store.add("test.lua", 3, "issue", "Comment", nil, "new")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local first_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  eq(1, #first_padding)

  -- Clear comments and re-align
  store.clear()
  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local second_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  eq(0, #second_padding)
end

T["align_buffers"]["does not add padding for file comments (they render on both sides)"] = function()
  store.add("test.lua", 0, "note", "File-level note")

  marks.render_for_buffer(orig_buf, "old", "test.lua")
  marks.render_for_buffer(mod_buf, "new", "test.lua")
  marks.align_buffers(orig_buf, mod_buf, "test.lua", "test.lua")

  local orig_padding = vim.api.nvim_buf_get_extmarks(orig_buf, ns_padding, 0, -1, {})
  local mod_padding = vim.api.nvim_buf_get_extmarks(mod_buf, ns_padding, 0, -1, {})
  eq(0, #orig_padding)
  eq(0, #mod_padding)
end

T["topfill for file comments"] = MiniTest.new_set()

T["topfill for file comments"]["sets topfill on windows displaying the buffer"] = function()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, mod_buf)

  store.add("test.lua", 0, "note", "File note")
  marks.render_for_buffer(mod_buf, "new", "test.lua")

  local view = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview()
  end)
  -- topfill should be set to the number of virt_lines (3 for a single-line comment)
  eq(3, view.topfill)
end

T["topfill for file comments"]["does not set topfill when window is scrolled past line 1"] = function()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, mod_buf)
  -- Scroll down
  vim.api.nvim_win_set_cursor(win, { 5, 0 })
  vim.cmd("normal! zt")

  store.add("test.lua", 0, "note", "File note")
  marks.render_for_buffer(mod_buf, "new", "test.lua")

  local view = vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview()
  end)
  -- topfill should not be changed when scrolled past line 1
  eq(0, view.topfill)
end

return T
