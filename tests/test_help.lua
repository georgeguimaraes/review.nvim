local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match

local keymaps = require("review.keymaps")
local t = keymaps._test

local T = MiniTest.new_set()

T["format_key"] = MiniTest.new_set()

T["format_key"]["passes through plain keys"] = function()
  eq("i", t.format_key("i"))
  eq("q", t.format_key("q"))
  eq("]n", t.format_key("]n"))
  eq("[n", t.format_key("[n"))
end

T["format_key"]["strips angle brackets from special keys"] = function()
  eq("Tab", t.format_key("<Tab>"))
  eq("S-Tab", t.format_key("<S-Tab>"))
  eq("Esc", t.format_key("<Esc>"))
end

T["format_key"]["converts C- to Ctrl-"] = function()
  eq("Ctrl-r", t.format_key("<C-r>"))
  eq("Ctrl-s", t.format_key("<C-s>"))
end

T["format_key"]["leaves <leader> as-is"] = function()
  eq("<leader>", t.format_key("<leader>"))
end

T["format_key"]["leaves leader-prefixed combos as-is"] = function()
  eq("<localleader>cn", t.format_key("<localleader>cn"))
end

T["add_section"] = MiniTest.new_set()

T["add_section"]["adds title and formatted entries"] = function()
  local entries = {
    { key = "i", desc = "Add comment" },
    { key = "e", desc = "Edit comment" },
  }
  local lines = {}
  t.add_section(entries, "Comments", lines, 5)

  eq(4, #lines)
  eq("", lines[1])
  eq("  Comments", lines[2])
  expect_match(lines[3], "i")
  expect_match(lines[3], "Add comment")
  expect_match(lines[4], "e")
  expect_match(lines[4], "Edit comment")
end

T["add_section"]["skips empty sections"] = function()
  local lines = {}
  t.add_section({}, "Empty", lines, 5)
  eq(0, #lines)
end

T["add_section"]["aligns columns based on max key width"] = function()
  local entries = {
    { key = "i", desc = "Short" },
    { key = "Ctrl-r", desc = "Long key" },
  }
  local lines = {}
  t.add_section(entries, "Test", lines, 6)

  -- Both descriptions should start at the same column
  local desc_col_1 = lines[3]:find("Short")
  local desc_col_2 = lines[4]:find("Long key")
  eq(desc_col_1, desc_col_2)
end

T["is_enabled"] = MiniTest.new_set()

T["is_enabled"]["returns true for string keys"] = function()
  eq(t.is_enabled("i"), true)
  eq(t.is_enabled("<C-r>"), true)
end

T["is_enabled"]["returns false for disabled keys"] = function()
  eq(t.is_enabled(false), false)
  eq(t.is_enabled(nil), false)
  eq(t.is_enabled(""), false)
end

return T
