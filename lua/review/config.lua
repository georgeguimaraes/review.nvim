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
---@field add_note string|false
---@field add_suggestion string|false
---@field add_issue string|false
---@field add_praise string|false
---@field delete_comment string|false
---@field edit_comment string|false
---@field next_comment string|false
---@field prev_comment string|false
---@field list_comments string|false
---@field export_clipboard string|false
---@field send_sidekick string|false
---@field clear_comments string|false
---@field close string|false
---@field toggle_readonly string|false
---@field next_file string|false
---@field prev_file string|false
---@field toggle_file_panel string|false
---@field readonly_add string|false
---@field readonly_delete string|false
---@field readonly_edit string|false
---@field popup_submit string|false
---@field popup_cancel string|false
---@field popup_cycle_type string|false

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
    -- Edit mode (leader-based)
    add_note = "<leader>cn",
    add_suggestion = "<leader>cs",
    add_issue = "<leader>ci",
    add_praise = "<leader>cp",
    delete_comment = "<leader>cd",
    edit_comment = "<leader>ce",
    -- Navigation
    next_comment = "]n",
    prev_comment = "[n",
    next_file = "<Tab>",
    prev_file = "<S-Tab>",
    toggle_file_panel = "f",
    -- Common actions
    list_comments = "c",
    export_clipboard = "C",
    send_sidekick = "S",
    clear_comments = "<C-r>",
    close = "q",
    toggle_readonly = "R",
    -- Readonly mode (simple keys)
    readonly_add = "i",
    readonly_delete = "d",
    readonly_edit = "e",
    -- Popup keymaps
    popup_submit = "<C-s>",
    popup_cancel = "q",
    popup_cycle_type = "<Tab>",
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
