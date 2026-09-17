-- End-to-end tests: drive review.nvim inside a child Neovim with real
-- codediff.nvim and nui.nvim, using keystrokes the way a user would.
local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match
local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()
local E = dofile("tests/e2e/helpers.lua")(child)
local wait_for, READY, wait_ready = E.wait_for, E.READY, E.wait_ready
local IN_POPUP, BACK_IN_DIFF = E.IN_POPUP, E.BACK_IN_DIFF

local sandbox = E.sandbox()

local LINES = 40 -- must match E.restart

local SCREENSHOT_OPTS = {
  directory = "tests/e2e/screenshots",
  -- Line 1 is codediff's tabline (abbreviated absolute path); the last line is
  -- the command line, where one-off installer messages and notifications land.
  ignore_text = { 1, LINES },
  ignore_attr = true, -- default highlight groups differ across nvim versions
}

local BEFORE = {
  ["api.lua"] = {
    "local M = {}",
    "",
    "function M.fetch(url)",
    "  local res = http.get(url)",
    "  return res.body",
    "end",
    "",
    "function M.parse(body)",
    "  return json.decode(body)",
    "end",
    "",
    "return M",
  },
  ["utils.lua"] = {
    "local M = {}",
    "",
    "function M.trim(s)",
    '  return s:match("^%s*(.-)%s*$")',
    "end",
    "",
    "return M",
  },
}

local AFTER = {
  ["api.lua"] = {
    "local M = {}",
    "",
    "function M.fetch(url)",
    "  local res = http.get(url)",
    "  if not res then",
    '    error("request failed: " .. url)',
    "  end",
    "  return res.body",
    "end",
    "",
    "function M.parse(body)",
    "  local ok, data = pcall(json.decode, body)",
    "  if not ok then",
    "    return nil",
    "  end",
    "  return data",
    "end",
    "",
    "return M",
  },
  ["utils.lua"] = {
    "local M = {}",
    "",
    "function M.trim(s)",
    '  if not s then return "" end',
    '  return s:match("^%s*(.-)%s*$")',
    "end",
    "",
    "function M.split(s, sep)",
    "  return vim.split(s, sep)",
    "end",
    "",
    "return M",
  },
}


-- A throwaway git repo with one commit and unstaged edits in two files.
local function make_repo()
  local dir = E.tempdir()
  for name, lines in pairs(BEFORE) do
    vim.fn.writefile(lines, dir .. "/" .. name)
  end
  E.git(dir, "init", "-q", "--initial-branch=main")
  E.git(dir, "add", ".")
  E.git(dir, "commit", "-q", "-m", "init")
  for name, lines in pairs(AFTER) do
    vim.fn.writefile(lines, dir .. "/" .. name)
  end
  return dir
end


-- Emoji icons carry U+FE0F (variation selector); screenstring() reports the
-- cell with or without it depending on redraw timing, so strip it.
local function screenshot()
  local shot = child.get_screenshot()
  for _, line in ipairs(shot.text) do
    for i, cell in ipairs(line) do
      line[i] = cell:gsub("\239\184\143", "")
    end
  end
  return shot
end

local function current_file()
  return child.lua_get([[(require("review.hooks").get_cursor_position())]])
end



local function open_review()
  child.cmd("Review")
  wait_ready("api.lua")
end

local function count()
  return child.lua_get([[require("review.store").count()]])
end

local function comment_summary()
  return child.lua_get([[table.concat(vim.tbl_map(function(c)
    return c.type .. "@" .. c.file .. ":" .. c.line
  end, require("review.store").get_all()), ",")]])
end

local function extmark_count()
  return child.lua_get([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {})]])
end


-- Add a comment on `line` through the popup: `tabs` cycles the type
-- (note -> suggestion -> issue -> praise), `<C-s>` submits.
local function add_comment(line, tabs, text)
  local before = count()
  child.type_keys(line .. "G", "i")
  wait_for(IN_POPUP, "comment popup")
  for _ = 1, tabs do
    child.type_keys("<Tab>")
  end
  child.type_keys(text, "<C-s>")
  wait_for(string.format([[require("review.store").count() == %d]], before + 1), "comment stored")
  wait_for(BACK_IN_DIFF, "focus back in diff")
end

local repo

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
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

T["opens review on the modified pane"] = function()
  eq(child.fn.exists(":Review"), 2)
  open_review()
  eq(count(), 0)
  expect.reference_screenshot(screenshot(), nil, SCREENSHOT_OPTS)
end

T["adds comments through the popup"] = function()
  open_review()

  child.type_keys("5G", "i")
  wait_for(IN_POPUP, "comment popup")
  expect.reference_screenshot(screenshot(), nil, SCREENSHOT_OPTS)
  child.type_keys("<Tab><Tab>", "error() here swallows the status code, return it too", "<C-s>")
  wait_for([[require("review.store").count() == 1]], "first comment stored")
  wait_for(BACK_IN_DIFF, "focus back in diff")

  add_comment(12, 3, "nice, pcall around decode is the right call")

  eq(comment_summary(), "issue@api.lua:5,praise@api.lua:12")
  wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) >= 2]], "marks rendered")
  expect.reference_screenshot(screenshot(), nil, SCREENSHOT_OPTS)
end

T["switches files with Tab and deletes with confirmation"] = function()
  open_review()
  child.type_keys("<Tab>")
  wait_ready("utils.lua")

  add_comment(4, 0, "should this return nil instead of empty string?")
  eq(comment_summary(), "note@utils.lua:4")
  wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) >= 1]], "mark rendered")

  -- `d` asks through vim.ui.select (inputlist by default): pick "1: Yes".
  child.type_keys("4G", "d")
  child.type_keys("1<CR>")
  wait_for([[require("review.store").count() == 0]], "comment deleted")
  wait_for([[#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("review"), 0, -1, {}) == 0]], "marks cleared")
  expect.reference_screenshot(screenshot(), nil, SCREENSHOT_OPTS)
end

T["exports to clipboard and closes"] = function()
  open_review()
  add_comment(5, 2, "error() here swallows the status code, return it too")
  add_comment(12, 3, "nice, pcall around decode is the right call")

  child.type_keys("C")
  wait_for([[vim.bo.filetype == "markdown"]], "export preview split")
  expect.reference_screenshot(screenshot(), nil, SCREENSHOT_OPTS)

  local exported = child.fn.getreg("+")
  expect_match(exported, "1%. %*%*%[ISSUE%]%*%* `api%.lua:5` %- error%(%) here swallows")
  expect_match(exported, "2%. %*%*%[PRAISE%]%*%* `api%.lua:12` %- nice, pcall")

  child.type_keys("q") -- close the preview split
  wait_for(READY, "focus back on modified pane")
  child.fn.setreg("+", "")

  child.type_keys("q") -- close the review, which exports again
  wait_for([[vim.fn.tabpagenr("$") == 1]], "review tab closed")
  expect_match(child.fn.getreg("+"), "%*%*%[ISSUE%]%*%* `api%.lua:5`")
  eq(child.lua_get([[require("review.hooks").get_current_tabpage()]]), vim.NIL)
end

return T
