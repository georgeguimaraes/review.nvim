-- Init for the mini.test runner. Unit tests run in this process; the e2e
-- tests spawn a child Neovim configured by tests/e2e/child_init.lua.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/deps/mini.test")

require("mini.test").setup()
