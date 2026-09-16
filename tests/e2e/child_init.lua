-- Init for the child Neovim driven by tests/e2e/test_*.lua. Loads review.nvim
-- with real codediff.nvim and nui.nvim from deps/ and keeps the UI stable so
-- reference screenshots stay deterministic.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/deps/nui.nvim")
vim.opt.rtp:prepend(root .. "/deps/codediff.nvim")
vim.opt.rtp:prepend(root)

vim.opt.swapfile = false
vim.opt.laststatus = 0
vim.opt.statusline = " " -- splits still get status lines; keep them free of temp paths
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.shortmess:append("I")

-- In-memory clipboard so `C` / `q` exports can be asserted via getreg('+')
-- without touching the system clipboard.
local clip = {}
vim.g.clipboard = {
  name = "e2e",
  copy = {
    ["+"] = function(lines) clip["+"] = lines end,
    ["*"] = function(lines) clip["*"] = lines end,
  },
  paste = {
    ["+"] = function() return clip["+"] or {} end,
    ["*"] = function() return clip["*"] or {} end,
  },
}

require("codediff").setup({})
require("review").setup({
  comment_types = {
    -- The default "⚠️" carries U+FE0F, which Neovim draws as 1 or 2 cells
    -- depending on redraw timing and shifts every screenshot row after it.
    issue = { icon = "⚠" },
  },
})
