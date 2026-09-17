local H = dofile("tests/helpers.lua")
local eq, expect_match = H.eq, H.expect_match

-- Run the check with vim.health's reporters replaced by recorders, so the
-- test doesn't depend on how :checkhealth renders (nightly does it async).
local function run_check()
  local lines = {}
  local health = vim.health
  local saved = {}
  for _, name in ipairs({ "start", "ok", "warn", "error", "info", "report_start", "report_ok", "report_warn", "report_error", "report_info" }) do
    saved[name] = health[name]
  end
  local function record(level)
    return function(msg)
      table.insert(lines, level .. " " .. msg)
    end
  end
  health.start, health.report_start = record("START"), record("START")
  health.ok, health.report_ok = record("OK"), record("OK")
  health.warn, health.report_warn = record("WARNING"), record("WARNING")
  health.error, health.report_error = record("ERROR"), record("ERROR")
  health.info, health.report_info = record("INFO"), record("INFO")

  package.loaded["review.health"] = nil -- it binds the reporters at load time
  local ok, err = pcall(function()
    require("review.health").check()
  end)
  for name, fn in pairs(saved) do
    health[name] = fn
  end
  package.loaded["review.health"] = nil
  if not ok then
    error(err)
  end
  return table.concat(lines, "\n")
end

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      require("review.config").setup()
    end,
  },
})

-- The unit runner has neither codediff nor nui on the runtimepath, so the
-- report must say so instead of erroring out.
T["reports missing codediff and nui as errors"] = function()
  local report = run_check()
  expect_match(report, "OK Neovim %d+%.%d+")
  expect_match(report, "OK git version")
  expect_match(report, "ERROR codediff.nvim not found")
  expect_match(report, "ERROR nui.nvim not found")
  expect_match(report, "clipboard provider: test") -- tests/minimal_init.lua's fake provider
end

T["mentions the on_export callback when configured"] = function()
  require("review.config").setup({ export = { on_export = function() end } })
  expect_match(run_check(), "on_export callback configured")
end

T["registers with :checkhealth"] = function()
  vim.cmd("checkhealth review")
  -- rendering is async on newer Neovim; give it a moment
  vim.wait(3000, function()
    return #vim.api.nvim_buf_get_lines(0, 0, -1, false) > 5
  end, 50)
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  vim.cmd("bwipeout!")
  expect_match(report, "review.nvim", true)
  expect_match(report, "codediff.nvim not found", true)
end

return T
