local M = {}

local config = require("review.config")
local comments = require("review.comments")
local export = require("review.export")

-- Track which buffers have keymaps set
local keymapped_buffers = {}

---@param bufnr number
local function set_buffer_keymaps(bufnr)
  if keymapped_buffers[bufnr] then
    return
  end

  local cfg = config.get()
  local km = cfg.keymaps
  local readonly = cfg.codediff.readonly

  local opts = { buffer = bufnr, noremap = true, silent = true, nowait = true }

  -- Simple keymaps in readonly mode
  if readonly then
    vim.keymap.set("n", "i", function() comments.add_with_menu() end, vim.tbl_extend("force", opts, { desc = "Add comment (pick type)" }))
    vim.keymap.set("n", "d", function() comments.delete_at_cursor() end, vim.tbl_extend("force", opts, { desc = "Delete comment" }))
    vim.keymap.set("n", "e", function() comments.edit_at_cursor() end, vim.tbl_extend("force", opts, { desc = "Edit comment" }))
  else
    -- Leader keymaps in edit mode
    vim.keymap.set("n", km.add_note, function() comments.add_at_cursor("note") end, vim.tbl_extend("force", opts, { desc = "Add note" }))
    vim.keymap.set("n", km.add_suggestion, function() comments.add_at_cursor("suggestion") end, vim.tbl_extend("force", opts, { desc = "Add suggestion" }))
    vim.keymap.set("n", km.add_issue, function() comments.add_at_cursor("issue") end, vim.tbl_extend("force", opts, { desc = "Add issue" }))
    vim.keymap.set("n", km.add_praise, function() comments.add_at_cursor("praise") end, vim.tbl_extend("force", opts, { desc = "Add praise" }))
    vim.keymap.set("n", km.delete_comment, function() comments.delete_at_cursor() end, vim.tbl_extend("force", opts, { desc = "Delete comment" }))
    vim.keymap.set("n", km.edit_comment, function() comments.edit_at_cursor() end, vim.tbl_extend("force", opts, { desc = "Edit comment" }))
  end

  -- File navigation (Tab/S-Tab to cycle files)
  vim.keymap.set("n", "<Tab>", function()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then return end
    local tabpage = vim.api.nvim_get_current_tabpage()
    local explorer_obj = lifecycle.get_explorer(tabpage)
    if explorer_obj then
      require("codediff.ui.explorer").navigate_next(explorer_obj)
    end
  end, vim.tbl_extend("force", opts, { desc = "Next file" }))

  vim.keymap.set("n", "<S-Tab>", function()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then return end
    local tabpage = vim.api.nvim_get_current_tabpage()
    local explorer_obj = lifecycle.get_explorer(tabpage)
    if explorer_obj then
      require("codediff.ui.explorer").navigate_prev(explorer_obj)
    end
  end, vim.tbl_extend("force", opts, { desc = "Previous file" }))

  -- Common keymaps
  vim.keymap.set("n", "c", function() comments.list() end, vim.tbl_extend("force", opts, { desc = "List all comments" }))
  vim.keymap.set("n", "C", function() require("review").clear() end, vim.tbl_extend("force", opts, { desc = "Clear all comments" }))
  vim.keymap.set("n", km.next_comment, function() comments.goto_next() end, vim.tbl_extend("force", opts, { desc = "Next comment" }))
  vim.keymap.set("n", km.prev_comment, function() comments.goto_prev() end, vim.tbl_extend("force", opts, { desc = "Previous comment" }))
  vim.keymap.set("n", km.export, function() export.to_clipboard() end, vim.tbl_extend("force", opts, { desc = "Export to clipboard" }))

  -- Close and export
  vim.keymap.set("n", "q", function() require("review").close() end, vim.tbl_extend("force", opts, { desc = "Close" }))

  -- Toggle readonly mode
  vim.keymap.set("n", "R", function() require("review").toggle_readonly() end, vim.tbl_extend("force", opts, { desc = "Toggle readonly mode" }))

  keymapped_buffers[bufnr] = true
end

-- Autocmd group for keymaps
local augroup = nil

---@param tabpage number
function M.setup_keymaps(tabpage)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    vim.notify("codediff.ui.lifecycle not available", vim.log.levels.WARN, { title = "Review" })
    return
  end

  -- Clear old autocmds
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
  end
  augroup = vim.api.nvim_create_augroup("review_keymaps", { clear = true })

  -- Reset tracking
  keymapped_buffers = {}

  -- Set keymaps on current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  set_buffer_keymaps(current_buf)

  -- Set up autocmd to apply keymaps when entering any buffer in this tabpage
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      -- Only apply if we're still in the codediff tabpage
      if vim.api.nvim_get_current_tabpage() ~= tabpage then
        return
      end

      -- Check if session still exists
      local sess = lifecycle.get_session(tabpage)
      if not sess then
        return
      end

      local bufnr = vim.api.nvim_get_current_buf()
      set_buffer_keymaps(bufnr)
    end,
  })

end

-- Clear keymaps tracking when readonly mode changes
function M.clear_keymaps()
  keymapped_buffers = {}
end

return M
