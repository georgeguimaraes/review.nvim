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

T["render_for_buffer with file_override"] = MiniTest.new_set()

T["render_for_buffer with file_override"]["renders comments using file_override path"] = function()
  store.add("src/app.lua", 3, "issue", "Fix this")

  -- Buffer has no name, but file_override provides the path
  marks.render_for_buffer(bufnr, nil, "src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
  eq(2, extmarks[1][2])
end

T["render_for_buffer with file_override"]["renders comments when buffer has codediff:// name that would fail parsing"] = function()
  -- Simulate the actual codediff URI format that breaks the old regex
  vim.api.nvim_buf_set_name(bufnr, "codediff:///Users/george/repo///abc123/src/app.lua")

  store.add("src/app.lua", 3, "note", "A note")

  -- Without file_override this would fail (old regex can't parse this URI)
  marks.render_for_buffer(bufnr, "new", "src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["render_for_buffer with file_override"]["normalizes file_override path (strips leading ./)"] = function()
  store.add("src/app.lua", 3, "issue", "Fix")

  marks.render_for_buffer(bufnr, nil, "./src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["render_for_buffer with file_override"]["normalizes file_override path (strips trailing slashes)"] = function()
  store.add("src/app.lua", 3, "issue", "Fix")

  marks.render_for_buffer(bufnr, nil, "src/app.lua/")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

T["render_for_buffer with file_override"]["renders nothing when file_override has no matching comments"] = function()
  store.add("other_file.lua", 3, "issue", "Fix")

  marks.render_for_buffer(bufnr, nil, "src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(0, #extmarks)
end

T["render_for_buffer with file_override"]["passes side through when using file_override"] = function()
  store.add("src/app.lua", 3, "issue", "Old side comment", nil, "old")

  -- Request "new" side: should not find the "old" comment
  marks.render_for_buffer(bufnr, "new", "src/app.lua")

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(0, #extmarks)
end

T["render_for_buffer with file_override"]["falls back to buffer name when file_override is nil"] = function()
  vim.api.nvim_buf_set_name(bufnr, "src/fallback.lua")

  store.add("src/fallback.lua", 3, "issue", "Fallback test")

  marks.render_for_buffer(bufnr, nil, nil)

  local ns_id = vim.api.nvim_create_namespace("review")
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  eq(1, #extmarks)
end

return T
