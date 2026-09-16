-- Regression cases for reported bugs. Each drives a real :Review session in a
-- child Neovim (see tests/e2e/child_init.lua) and asserts the fixed behavior.
local H = dofile("tests/helpers.lua")
local eq, neq, expect_match, expect_no_match = H.eq, H.neq, H.expect_match, H.expect_no_match
local child = MiniTest.new_child_neovim()

local sandbox = vim.fn.tempname()
vim.fn.mkdir(sandbox, "p")
vim.env.XDG_DATA_HOME = sandbox .. "/data"
vim.env.XDG_STATE_HOME = sandbox .. "/state"
vim.env.XDG_CACHE_HOME = sandbox .. "/cache"
vim.env.XDG_CONFIG_HOME = sandbox .. "/config"

local function git(dir, ...)
  local cmd = { "git", "-C", dir, "-c", "user.name=e2e", "-c", "user.email=e2e@test", "-c", "commit.gpgsign=false", ... }
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error("git failed: " .. table.concat(cmd, " ") .. "\n" .. out)
  end
end

-- Two changed files, one of them markdown (issue #30).
local function make_repo()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  dir = vim.uv.fs_realpath(dir)
  vim.fn.writefile({ "# Title", "", "Some text." }, dir .. "/README.md")
  vim.fn.writefile({ "local M = {}", "", "function M.a()", "  return 1", "end", "", "return M" }, dir .. "/api.lua")
  git(dir, "init", "-q", "--initial-branch=main")
  git(dir, "add", ".")
  git(dir, "commit", "-q", "-m", "init")
  vim.fn.writefile({ "# Title", "", "Some text.", "", "More text." }, dir .. "/README.md")
  vim.fn.writefile({ "local M = {}", "", "function M.a()", "  if true then", "    return 2", "  end", "end", "", "return M" }, dir .. "/api.lua")
  return dir
end

local function wait_for(pred, what, timeout_ms)
  local deadline = vim.uv.hrtime() + (timeout_ms or 5000) * 1e6
  while true do
    if child.is_blocked() then
      child.type_keys("<CR>")
    elseif child.lua_get(pred) then
      return
    end
    if vim.uv.hrtime() > deadline then
      error("timed out waiting for " .. what)
    end
    vim.uv.sleep(50)
  end
end

local READY = [[(function()
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then return false end
  local _, mod_buf = lifecycle.get_buffers(vim.api.nvim_get_current_tabpage())
  return mod_buf ~= nil
    and vim.api.nvim_get_current_buf() == mod_buf
    and vim.fn.maparg("i", "n") ~= ""
    and not vim.bo.modifiable
    and vim.api.nvim_buf_line_count(0) > 1
end)()]]

local function open_review()
  child.cmd("Review")
  wait_for(READY, "review ready", 15000)
end

local IN_POPUP = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.mode() == "i"]]

-- Review's buffer-local normal-mode mappings present in the current buffer.
local REVIEW_MAPS = [[(function()
  local out = {}
  for _, key in ipairs({ "i", "q", "c", "d", "e", "C", "]n" }) do
    local m = vim.fn.maparg(key, "n", false, true)
    if m.buffer == 1 and m.desc and (m.desc:find("omment") or m.desc == "Close" or m.desc:find("clipboard")) then
      out[#out + 1] = key
    end
  end
  return table.concat(out, ",")
end)()]]

-- The explorer window: the non-floating window that shows neither diff buffer.
local EXPLORER_WIN = [[(function()
  local lifecycle = require("codediff.ui.lifecycle")
  local tab = vim.api.nvim_get_current_tabpage()
  local orig_buf, mod_buf = lifecycle.get_buffers(tab)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf ~= orig_buf and buf ~= mod_buf and vim.api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
end)()]]

local repo

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "tests/e2e/child_init.lua", "-i", "NONE" })
      child.o.lines, child.o.columns = 40, 160
      repo = make_repo()
      child.cmd("cd " .. vim.fn.fnameescape(repo))
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

T["#31 explorer buffer keeps codediff's own keymaps"] = function()
  open_review()
  local explorer_win = child.lua_get(EXPLORER_WIN)
  neq(explorer_win, vim.NIL)
  child.api.nvim_set_current_win(explorer_win)
  vim.uv.sleep(300) -- let BufEnter handlers run
  eq(child.lua_get(REVIEW_MAPS), "")
  -- and the diff pane still has them
  child.lua([[vim.api.nvim_set_current_win((select(2, require("codediff.ui.lifecycle").get_windows(vim.api.nvim_get_current_tabpage()))))]])
  neq(child.lua_get(REVIEW_MAPS), "")
end

T["#31 switching files does not refocus the modified pane"] = function()
  open_review()
  child.lua([[
    local hooks = require("review.hooks")
    _G.FOCUS_CALLS = 0
    local orig = hooks._focus_modified_pane
    hooks._focus_modified_pane = function(...)
      _G.FOCUS_CALLS = _G.FOCUS_CALLS + 1
      return orig(...)
    end
  ]])
  child.type_keys("<Tab>")
  wait_for([[(require("review.hooks").get_cursor_position()) == "api.lua"]], "file switched", 10000)
  vim.uv.sleep(600) -- longer than review's deferred refocus (100ms + 150ms)
  eq(child.lua_get([[_G.FOCUS_CALLS]]), 0)
  -- keymaps survived the switch on the new modified buffer
  wait_for(READY, "keymaps on new file")
end

T["#30 comment popup keeps its own keymaps"] = function()
  open_review()
  child.type_keys("3G", "i")
  wait_for(IN_POPUP, "popup")
  eq(child.lua_get(REVIEW_MAPS), "")
  child.type_keys("<Tab>", "still works", "<C-s>")
  wait_for([[require("review.store").count() == 1]], "comment stored")
  eq(child.lua_get([[require("review.store").get_all()[1].type]]), "suggestion")
end

T["#30 review does not fire FileType on the diff buffers it highlights"] = function()
  child.lua([[
    _G.FT_FIRES = {}
    vim.api.nvim_create_autocmd("FileType", {
      callback = function(ev) _G.FT_FIRES[ev.buf] = (_G.FT_FIRES[ev.buf] or 0) + 1 end,
    })
  ]])
  open_review()
  vim.uv.sleep(300)
  -- The original side is codediff's virtual buffer: only review touches it.
  local orig_fires = child.lua_get([[_G.FT_FIRES[(require("codediff.ui.lifecycle").get_buffers(vim.api.nvim_get_current_tabpage()))] or 0]])
  eq(orig_fires, 0)
  -- highlighting still comes from treesitter
  eq(child.lua_get([[vim.treesitter.highlighter.active[(require("codediff.ui.lifecycle").get_buffers(vim.api.nvim_get_current_tabpage()))] ~= nil]]), true)
end

T["#38 closing the review restores modifiable on the working-tree buffer"] = function()
  open_review()
  local mod_buf = child.lua_get([[select(2, require("codediff.ui.lifecycle").get_buffers(vim.api.nvim_get_current_tabpage()))]])
  eq(child.api.nvim_get_option_value("modifiable", { buf = mod_buf }), false) -- readonly mode is on
  child.type_keys("q")
  wait_for([[vim.fn.tabpagenr("$") == 1]], "review closed")
  if child.api.nvim_buf_is_valid(mod_buf) then
    eq(child.api.nvim_get_option_value("modifiable", { buf = mod_buf }), true)
    eq(child.api.nvim_get_option_value("readonly", { buf = mod_buf }), false)
  end
  -- what a user does next: open the file normally and expect to edit it
  child.cmd("edit " .. vim.fn.fnameescape(repo .. "/api.lua"))
  eq(child.lua_get([[vim.bo.modifiable]]), true)
  eq(child.lua_get([[vim.bo.readonly]]), false)
end

T["#40 popup title shows the configured submit key"] = function()
  child.lua([[require("review.config").setup({ keymaps = { popup_submit = "<C-CR>" } })]])
  open_review()
  child.type_keys("3G", "i")
  wait_for(IN_POPUP, "popup")
  local screen = table.concat(vim.tbl_map(function(line) return table.concat(line) end, child.get_screenshot().text), "\n")
  expect_match(screen, "Comment (C-CR: submit)", true)
  expect_no_match(screen, "C-s: submit", true)
end

return T
