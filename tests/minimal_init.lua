-- Init for the mini.test runner. Unit tests run in this process; the e2e
-- tests spawn a child Neovim configured by tests/e2e/child_init.lua.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/deps/mini.test")

-- Unit tests call export/store code paths that write the clipboard; keep it
-- in memory so a test run never clobbers the real one.
local clip = {}
vim.g.clipboard = {
  name = "test",
  copy = { ["+"] = function(lines) clip["+"] = lines end, ["*"] = function(lines) clip["*"] = lines end },
  paste = { ["+"] = function() return clip["+"] or {} end, ["*"] = function() return clip["*"] or {} end },
}

require("mini.test").setup()
