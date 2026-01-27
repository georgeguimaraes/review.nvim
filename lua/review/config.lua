local M = {}

---@class ReviewConfig
---@field comment_types table<string, CommentType>
---@field keymaps ReviewKeymaps
---@field export ReviewExportConfig
---@field codediff ReviewCodediffConfig

---@class CommentType
---@field key string
---@field name string
---@field icon string
---@field hl string
---@field line_hl string

---@class ReviewKeymaps
---@field add_note string
---@field add_suggestion string
---@field add_issue string
---@field add_praise string
---@field delete_comment string
---@field edit_comment string
---@field next_comment string
---@field prev_comment string
---@field list_comments string
---@field comments_to_clipboard string
---@field comments_to_sidekick string
---@field clear_comments string
---@field close string
---@field toggle_readonly string

---@class ReviewExportConfig
---@field context_lines number
---@field include_file_stats boolean

---@class ReviewCodediffConfig
---@field readonly boolean

---@type ReviewConfig
M.defaults = {
  comment_types = {
    note = { key = "n", name = "Note", icon = "📝", hl = "ReviewNote", line_hl = "ReviewNoteLine" },
    suggestion = { key = "s", name = "Suggestion", icon = "💡", hl = "ReviewSuggestion", line_hl = "ReviewSuggestionLine" },
    issue = { key = "i", name = "Issue", icon = "⚠️", hl = "ReviewIssue", line_hl = "ReviewIssueLine" },
    praise = { key = "p", name = "Praise", icon = "✨", hl = "ReviewPraise", line_hl = "ReviewPraiseLine" },
  },
  keymaps = {
    add_note = "<leader>cn",
    add_suggestion = "<leader>cs",
    add_issue = "<leader>ci",
    add_praise = "<leader>cp",
    delete_comment = "<leader>cd",
    edit_comment = "<leader>ce",
    next_comment = "]n",
    prev_comment = "[n",
    list_comments = "c",
    comments_to_clipboard = "C",
    comments_to_sidekick = "S",
    clear_comments = "<C-r>",
    close = "q",
    toggle_readonly = "R",
  },
  export = {
    context_lines = 3,
    include_file_stats = true,
  },
  codediff = {
    readonly = true,
  },
}

---@type ReviewConfig
M.config = vim.deepcopy(M.defaults)

---@param opts? ReviewConfig
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@return ReviewConfig
function M.get()
  return M.config
end

return M
