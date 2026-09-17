-- Notes on any file: :Review note works in ordinary buffers, renders there,
-- and ends up in the review and the export like any other comment.
local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match
local child = MiniTest.new_child_neovim()
local E = dofile("tests/e2e/helpers.lua")(child)

local sandbox = E.sandbox()

local API_BASE = { "local M = {}", "", "function M.a()", "  return 1", "end", "", "return M" }
local API_NEW = { "local M = {}", "", "function M.a()", "  if true then", "    return 2", "  end", "end", "", "return M" }

local function make_repo()
  local dir = E.tempdir()
  vim.fn.writefile(API_BASE, dir .. "/api.lua")
  vim.fn.writefile({ "local M = {}", "", "return M" }, dir .. "/utils.lua")
  E.git(dir, "init", "-q", "--initial-branch=main")
  E.git(dir, "add", ".")
  E.git(dir, "commit", "-q", "-m", "init")
  vim.fn.writefile(API_NEW, dir .. "/api.lua")
  return dir
end

local function extmark_count()
  return child.lua_get([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {})]])
end

local function summary()
  return child.lua_get([[table.concat(vim.tbl_map(function(c)
    return c.type .. "@" .. c.file .. ":" .. c.line .. (c.line_end and ("-" .. c.line_end) or "")
  end, require("review.store").get_all()), ",")]])
end

local function add_note_here(text)
  child.cmd("Review note")
  E.wait_for(E.IN_POPUP, "popup")
  child.type_keys(text, "<C-s>")
  E.wait_for(E.BACK_IN_DIFF, "popup closed")
end

local repo

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      vim.fn.delete(sandbox .. "/data/nvim/review", "rf")
      repo = make_repo()
      E.restart(repo)
    end,
    post_case = function()
      if repo then
        vim.fn.delete(repo, "rf")
      end
    end,
    post_once = function()
      child.stop()
      vim.fn.delete(sandbox, "rf")
    end,
  },
})

T["adds a note on the current line of a plain buffer"] = function()
  child.cmd("edit api.lua")
  child.type_keys("3G")
  add_note_here("plain note")
  eq(summary(), "note@api.lua:3")
  E.wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) >= 1]], "note rendered")
end

T["adds a range note from a visual selection"] = function()
  child.cmd("edit utils.lua")
  child.type_keys("V", "2j", ":Review note<CR>")
  E.wait_for(E.IN_POPUP, "popup")
  child.type_keys("range note", "<C-s>")
  E.wait_for([[require("review.store").count() == 1]], "note stored")
  eq(summary(), "note@utils.lua:1-3")
end

T["renders notes when the file is opened again"] = function()
  child.cmd("edit api.lua")
  child.type_keys("2G")
  add_note_here("sticky")
  child.cmd("edit utils.lua")
  eq(extmark_count(), 0)
  child.cmd("edit api.lua")
  E.wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) >= 1]], "note re-rendered")
end

T["notes appear in the review and in the export"] = function()
  child.cmd("edit api.lua")
  child.type_keys("4G")
  add_note_here("seen from the diff too")
  child.cmd("Review")
  E.wait_ready("api.lua")
  E.wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) >= 1]], "note on the diff pane")
  child.type_keys("C")
  E.wait_for([[vim.bo.filetype == "markdown"]], "preview")
  expect_match(child.fn.getreg("+"), "%*%*%[NOTE%]%*%* `api%.lua:4` %- seen from the diff too")
end

T["edits and deletes the note at the cursor"] = function()
  child.cmd("edit api.lua")
  child.type_keys("3G")
  add_note_here("first draft")
  child.cmd("Review edit")
  E.wait_for(E.IN_POPUP, "edit popup")
  child.type_keys("<Esc>", "ggdG", "i", "final", "<C-s>") -- replace the prefilled text
  E.wait_for([[(require("review.store").get_all()[1] or {}).text == "final"]], "note updated")
  -- typed, not child.cmd: the confirmation prompt would block a synchronous request
  child.type_keys(":Review delete<CR>", "1<CR>")
  E.wait_for([[require("review.store").count() == 0]], "note deleted")
  E.wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) == 0]], "mark removed")
end

T["notes follow edits once the file is written"] = function()
  child.cmd("edit api.lua")
  child.type_keys("3G")
  add_note_here("on the function")
  child.type_keys("gg", "O", "-- new first line", "<Esc>")
  child.cmd("write")
  E.wait_for([[require("review.store").get_all()[1].line == 4]], "note moved to line 4")
  eq(child.api.nvim_buf_get_lines(0, 3, 4, false), { "function M.a()" })
end

T["refuses files outside the repository"] = function()
  local outside = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "elsewhere" }, outside)
  child.cmd("edit " .. vim.fn.fnameescape(outside))
  child.cmd("Review note")
  vim.uv.sleep(200)
  eq(child.lua_get([[require("review.store").count()]]), 0)
  expect_match(child.lua_get([[vim.fn.execute("messages")]]), "Could not determine cursor position", true)
  vim.fn.delete(outside)
end

return T
