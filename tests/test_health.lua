local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match

local function run_checkhealth()
  vim.cmd("checkhealth review")
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  vim.cmd("bwipeout!")
  return report
end

local T = MiniTest.new_set()

-- The unit runner has neither codediff nor nui on the runtimepath, so the
-- report must say so instead of erroring out.
T["reports missing codediff and nui as errors"] = function()
  local report = run_checkhealth()
  expect_match(report, "OK Neovim %d+%.%d+")
  expect_match(report, "OK git version")
  expect_match(report, "ERROR codediff.nvim not found")
  expect_match(report, "ERROR nui.nvim not found")
  expect_match(report, "clipboard provider: test") -- tests/minimal_init.lua's fake provider
end

T["mentions the on_export callback when configured"] = function()
  local config = require("review.config")
  config.setup({ export = { on_export = function() end } })
  local report = run_checkhealth()
  expect_match(report, "on_export callback configured")
  config.setup()
end

return T
