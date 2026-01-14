local M = {}

function M.setup()
  local links = {
    ReviewNote = "DiagnosticInfo",
    ReviewSuggestion = "DiagnosticHint",
    ReviewIssue = "DiagnosticWarn",
    ReviewPraise = "DiagnosticOk",
    ReviewSign = "Comment",
    ReviewVirtText = "Comment",
  }

  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  -- Line highlights (darker background, no underline)
  vim.api.nvim_set_hl(0, "ReviewNoteLine", { bg = "#0d1f28", underline = false, default = true })
  vim.api.nvim_set_hl(0, "ReviewSuggestionLine", { bg = "#152015", underline = false, default = true })
  vim.api.nvim_set_hl(0, "ReviewIssueLine", { bg = "#28250d", underline = false, default = true })
  vim.api.nvim_set_hl(0, "ReviewPraiseLine", { bg = "#15152a", underline = false, default = true })

  vim.fn.sign_define("ReviewComment", {
    text = "●",
    texthl = "ReviewSign",
  })
end

return M
