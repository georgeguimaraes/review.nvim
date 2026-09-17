-- Notes outside the diff view: resolving a plain buffer to a repo-relative
-- file and rendering comments on it.
local H = dofile("tests/helpers.lua")
local eq, neq = H.eq, H.neq

local utils = require("review.utils")
local hooks = require("review.hooks")
local store = require("review.store")
local marks = require("review.marks")
local config = require("review.config")

local bufnr

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()
    end,
    post_case = function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      bufnr = nil
    end,
  },
})

T["relative_to_root"] = MiniTest.new_set()

T["relative_to_root"]["makes paths inside the repo root-relative"] = function()
  eq(utils.relative_to_root("lua/review/init.lua"), "lua/review/init.lua")
  eq(utils.relative_to_root(vim.fn.getcwd() .. "/lua/review/init.lua"), "lua/review/init.lua")
  eq(utils.relative_to_root("./lua/review/init.lua"), "lua/review/init.lua")
end

T["relative_to_root"]["returns nil outside the repo"] = function()
  eq(utils.relative_to_root(vim.fn.tempname() .. "/x.lua"), nil)
  eq(utils.relative_to_root(vim.fn.getcwd()), nil)
  eq(utils.relative_to_root(""), nil)
end

T["get_cursor_position"] = MiniTest.new_set()

T["get_cursor_position"]["falls back to the current file buffer when no review is open"] = function()
  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, "tests/notes_target.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local file, line, side = hooks.get_cursor_position()
  eq(file, "tests/notes_target.lua")
  eq(line, 2)
  eq(side, "new")
end

T["get_cursor_position"]["refuses scratch buffers"] = function()
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "tests/scratch.lua")
  vim.api.nvim_set_current_buf(bufnr)
  eq(hooks.get_cursor_position(), nil)
end

T["render_plain_buffer"] = MiniTest.new_set()

T["render_plain_buffer"]["draws marks for the buffer's file"] = function()
  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, "tests/notes_target.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(bufnr)
  store.add("tests/notes_target.lua", 3, "note", "look here")

  marks.render_plain_buffer(bufnr)
  local ns = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  eq(#extmarks, 1)
  eq(extmarks[1][2], 2)
  neq(extmarks[1][4].virt_lines, nil)
end

T["sync_positions"] = MiniTest.new_set()

local function open_target(lines)
  bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, "tests/notes_target.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
end

T["sync_positions"]["follows lines inserted above a note"] = function()
  open_target({ "one", "two", "three" })
  local comment = store.add("tests/notes_target.lua", 3, "note", "on three")
  marks.render_plain_buffer(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "added", "added" })
  eq(marks.sync_positions(bufnr), 1)
  eq(store.get(comment.id).line, 5)
  eq(vim.api.nvim_buf_get_lines(bufnr, 4, 5, false), { "three" })
end

T["sync_positions"]["keeps both ends of a range"] = function()
  open_target({ "one", "two", "three", "four" })
  local comment = store.add("tests/notes_target.lua", 2, "note", "two to three", 3)
  marks.render_plain_buffer(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {}) -- delete line one
  eq(marks.sync_positions(bufnr), 1)
  eq(store.get(comment.id).line, 1)
  eq(store.get(comment.id).line_end, 2)
end

T["sync_positions"]["reports nothing moved when nothing changed"] = function()
  open_target({ "one", "two" })
  store.add("tests/notes_target.lua", 2, "note", "still here")
  marks.render_plain_buffer(bufnr)
  eq(marks.sync_positions(bufnr), 0)
end

return T
