local H = dofile("tests/helpers.lua")
local eq = H.eq

local store = require("review.store")
local marks = require("review.marks")
local config = require("review.config")

local bufnr

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
      config.setup()

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "local M = {}",
        "",
        "function M.hello()",
        "  print('hello')",
        "end",
        "",
        "return M",
      })
      vim.api.nvim_set_current_buf(bufnr)
    end,
    post_case = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end,
  },
})

T["monorepo path mismatch"] = MiniTest.new_set()

-- Simulates the real bug: CWD is a subdirectory of git_root (e.g., backend/ngen/),
-- so lifecycle.get_paths() returns paths relative to CWD (e.g., ".github/workflows/ci.yml")
-- but comments are stored relative to git_root (e.g., "backend/ngen/.github/workflows/ci.yml").
-- render_for_buffer must use the git_root-relative path to find stored comments.

T["monorepo path mismatch"]["finds comments when stored with git-root-relative path but buffer uses CWD-relative path"] = function()
  -- Comment stored with full git-root-relative path (as get_cursor_position does)
  store.add("backend/ngen/.github/workflows/ci.yml", 3, "issue", "Fix this workflow")

  -- Rendering uses git-root-relative path via file_override (after relativization fix)
  marks.render_for_buffer(bufnr, "new", "backend/ngen/.github/workflows/ci.yml")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["monorepo path mismatch"]["does NOT find comments when file_override uses wrong relative base"] = function()
  -- Comment stored with git-root-relative path
  store.add("backend/ngen/.github/workflows/ci.yml", 3, "issue", "Fix this workflow")

  -- If we pass CWD-relative path (the bug), it won't match
  marks.render_for_buffer(bufnr, "new", ".github/workflows/ci.yml")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(0, #extmarks)
end

T["monorepo path mismatch"]["renders on both sides with git-root-relative paths"] = function()
  store.add("backend/ngen/src/app.lua", 3, "note", "Old side note", nil, "old")
  store.add("backend/ngen/src/app.lua", 3, "suggestion", "New side suggestion", nil, "new")

  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, {
    "line 1", "line 2", "line 3", "line 4",
  })

  marks.render_for_buffer(orig_buf, "old", "backend/ngen/src/app.lua")
  marks.render_for_buffer(bufnr, "new", "backend/ngen/src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local orig_marks = vim.api.nvim_buf_get_extmarks(orig_buf, ns_id, 0, -1, { details = true })
  local mod_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #orig_marks)
  eq(1, #mod_marks)

  vim.api.nvim_buf_delete(orig_buf, { force = true })
end

T["path consistency between store and render"] = MiniTest.new_set()

T["path consistency between store and render"]["comment stored and rendered with same normalized path are found"] = function()
  local path = "src/components/Button.tsx"
  store.add(path, 3, "issue", "Needs accessibility attrs")
  marks.render_for_buffer(bufnr, "new", path)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["path consistency between store and render"]["comment stored with leading ./ is found when rendered without"] = function()
  -- normalize_path strips leading ./ so both should match
  store.add("src/app.lua", 3, "issue", "Fix")
  marks.render_for_buffer(bufnr, nil, "./src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["path consistency between store and render"]["multiple comments on same git-root-relative file all render"] = function()
  local path = "backend/ngen/lib/utils.ex"
  store.add(path, 1, "note", "First")
  store.add(path, 3, "issue", "Second")
  store.add(path, 5, "suggestion", "Third")

  marks.render_for_buffer(bufnr, nil, path)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(3, #extmarks)
end

return T
