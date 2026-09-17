-- Shared helpers for the e2e files. Each file has its own child Neovim:
--   local E = dofile("tests/e2e/helpers.lua")(child)
return function(child)
  local E = {}

  -- A scratch dir the child's XDG dirs point at, so persisted comments never
  -- land in the real ~/.local/share/nvim/review. The env is applied in
  -- E.restart, since all test files are loaded before any child starts.
  local sandbox_dir
  function E.sandbox()
    sandbox_dir = vim.fn.tempname()
    vim.fn.mkdir(sandbox_dir, "p")
    return sandbox_dir
  end

  -- A fresh temp dir with symlinks resolved (macOS: /var -> /private/var,
  -- which has to match what git reports as the root).
  function E.tempdir()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    return vim.uv.fs_realpath(dir)
  end

  function E.git(dir, ...)
    local cmd = { "git", "-C", dir, "-c", "user.name=e2e", "-c", "user.email=e2e@test", "-c", "commit.gpgsign=false", ... }
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      error("git failed: " .. vim.inspect(cmd) .. "\n" .. out)
    end
    return out
  end

  -- Restart the child on a repo with a stable window size.
  function E.restart(repo)
    if sandbox_dir then
      vim.env.XDG_DATA_HOME = sandbox_dir .. "/data"
      vim.env.XDG_STATE_HOME = sandbox_dir .. "/state"
      vim.env.XDG_CACHE_HOME = sandbox_dir .. "/cache"
      vim.env.XDG_CONFIG_HOME = sandbox_dir .. "/config"
    end
    child.restart({ "-u", "tests/e2e/child_init.lua", "-i", "NONE" })
    child.o.lines, child.o.columns = 40, 160
    child.cmd("cd " .. vim.fn.fnameescape(repo))
  end

  -- Poll a Lua predicate inside the child from the parent, so the child's
  -- event loop keeps running and queued keys get dispatched.
  function E.wait_for(pred, what, timeout_ms)
    local deadline = vim.uv.hrtime() + (timeout_ms or 5000) * 1e6
    while true do
      if child.is_blocked() then
        child.type_keys("<CR>") -- dismiss hit-enter prompts from vim.notify
      elseif child.lua_get(pred) then
        return
      end
      if vim.uv.hrtime() > deadline then
        error("timed out waiting for " .. what)
      end
      vim.uv.sleep(50)
    end
  end

  -- Review's keymaps are installed and focus has landed on the modified pane.
  E.READY = [[(function()
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if not ok then return false end
    local _, mod_buf = lifecycle.get_buffers(vim.api.nvim_get_current_tabpage())
    return mod_buf ~= nil
      and vim.api.nvim_get_current_buf() == mod_buf
      and vim.fn.maparg("i", "n") ~= ""
      and not vim.bo.modifiable
      and vim.api.nvim_buf_line_count(0) > 1
  end)()]]

  -- Both conditions in one predicate: after a file switch the old buffer is
  -- "ready" until codediff swaps in the new one, which then needs its own setup.
  function E.wait_ready(file)
    local pred = string.format([[%s and (require("review.hooks").get_cursor_position()) == %q]], E.READY, file)
    E.wait_for(pred, "review keymaps on modified pane showing " .. file, 15000)
  end

  E.IN_POPUP = [[vim.api.nvim_win_get_config(0).relative ~= "" and vim.fn.mode() == "i"]]
  E.BACK_IN_DIFF = [[vim.api.nvim_win_get_config(0).relative == "" and vim.fn.mode() == "n"]]

  -- Text of the explorer window (the non-floating window showing neither diff buffer).
  E.EXPLORER_TEXT = [[(function()
    local lifecycle = require("codediff.ui.lifecycle")
    local tab = vim.api.nvim_get_current_tabpage()
    local orig_buf, mod_buf = lifecycle.get_buffers(tab)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if buf ~= orig_buf and buf ~= mod_buf and vim.api.nvim_win_get_config(win).relative == "" then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      end
    end
    return ""
  end)()]]

  return E
end
