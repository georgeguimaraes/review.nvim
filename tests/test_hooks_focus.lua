local H = dofile("tests/helpers.lua")
local eq = H.eq

local hooks = require("review.hooks")

local mod_buf, mod_win, other_win

-- Captured once so post_case can always put the real function back, even if a case
-- fails partway through after stubbing it (all mini.test files share one process).
local original_get_config = vim.api.nvim_win_get_config

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      mod_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(mod_buf, 0, -1, false, { "new line" })

      other_win = vim.api.nvim_get_current_win()

      vim.cmd("vsplit")
      mod_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(mod_win, mod_buf)
    end,
    post_case = function()
      vim.api.nvim_win_get_config = original_get_config

      if vim.api.nvim_buf_is_valid(mod_buf) then
        vim.api.nvim_buf_delete(mod_buf, { force = true })
      end

      while #vim.api.nvim_tabpage_list_wins(0) > 1 do
        vim.cmd("quit")
      end
    end,
  },
})

T["focuses the modified pane normally"] = function()
  local tabpage = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(other_win)
  eq(other_win, vim.api.nvim_get_current_win())

  local lifecycle = {
    get_session = function()
      return { modified_win = mod_win }
    end,
  }

  hooks._focus_modified_pane(lifecycle, tabpage)

  eq(mod_win, vim.api.nvim_get_current_win())
end

T["should not steal focus from floating windows"] = function()
  local tabpage = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(other_win)

  local lifecycle = {
    get_session = function()
      return { modified_win = mod_win }
    end,
  }

  -- Stub nvim_win_get_config to simulate current window being a float
  vim.api.nvim_win_get_config = function(win)
    if win == vim.api.nvim_get_current_win() then
      return { relative = "cursor", width = 40, height = 5 }
    end
    return original_get_config(win)
  end

  hooks._focus_modified_pane(lifecycle, tabpage)

  -- Focus should stay on the current window, not jump to mod_win
  eq(other_win, vim.api.nvim_get_current_win())

  vim.api.nvim_win_get_config = original_get_config
end

return T
