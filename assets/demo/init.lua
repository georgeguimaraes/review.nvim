-- Neovim config for recording the README demo (see assets/demo.tape).
-- Run from the repo root after `make deps`. REVIEW_DEMO_DIR is the repo to review.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/deps/nui.nvim")
vim.opt.rtp:prepend(root .. "/deps/codediff.nvim")
vim.opt.rtp:prepend(root)

vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.opt.showtabline = 0
vim.opt.statusline = " %t %m"
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.shortmess:append("I")
vim.cmd.colorscheme("default")

-- Keep the export off the real clipboard while recording.
local clip = {}
vim.g.clipboard = {
  name = "demo",
  copy = { ["+"] = function(lines) clip["+"] = lines end, ["*"] = function(lines) clip["*"] = lines end },
  paste = { ["+"] = function() return clip["+"] or {} end, ["*"] = function() return clip["*"] or {} end },
}

require("codediff").setup({})
require("review").setup({})

if vim.env.REVIEW_DEMO_DIR then
  vim.cmd.cd(vim.env.REVIEW_DEMO_DIR)
end
