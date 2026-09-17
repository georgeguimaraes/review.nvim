-- :checkhealth review
local M = {}

local health = vim.health
-- Neovim 0.9 only has the report_* names
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local err = health.error or health.report_error
local info = health.info or health.report_info

---@param mod string
---@param names string[]
---@return string[] missing
local function missing_functions(mod, names)
  local loaded, m = pcall(require, mod)
  if not loaded then
    return names
  end
  local missing = {}
  for _, name in ipairs(names) do
    if type(m[name]) ~= "function" then
      table.insert(missing, name)
    end
  end
  return missing
end

local function check_codediff()
  local loaded = pcall(require, "codediff")
  if not loaded then
    err("codediff.nvim not found", { "Install esmuellert/codediff.nvim, review.nvim renders on top of it" })
    return
  end
  local has_version, version = pcall(require, "codediff.version")
  ok("codediff.nvim " .. ((has_version and version.VERSION) or "(unknown version)"))

  -- The accessors review.nvim calls. codediff has renamed these before
  -- (get_paths return shape in Jul 2026, get_explorer -> get_panel in 4.0.6).
  local missing = missing_functions("codediff.ui.lifecycle", { "get_session", "get_buffers", "get_paths", "get_windows", "get_git_context", "set_tab_keymap" })
  if #missing > 0 then
    err("codediff.ui.lifecycle is missing: " .. table.concat(missing, ", "), { "This codediff version doesn't match review.nvim. Update both to their latest releases" })
  else
    ok("codediff.ui.lifecycle API")
  end

  local explorer_missing = missing_functions("codediff.ui.lifecycle", { "get_panel" })
  if #explorer_missing > 0 and #missing_functions("codediff.ui.lifecycle", { "get_explorer" }) > 0 then
    err("codediff exposes neither get_panel nor get_explorer", { "File navigation (Tab, S-Tab, f) won't work. Update codediff.nvim" })
  else
    ok("codediff explorer accessor")
  end

  local nav_missing = missing_functions("codediff.ui.explorer", { "navigate_next", "navigate_prev", "toggle_visibility" })
  if #nav_missing > 0 then
    err("codediff.ui.explorer is missing: " .. table.concat(nav_missing, ", "), { "File navigation keymaps won't work. Update codediff.nvim" })
  else
    ok("codediff.ui.explorer navigation API")
  end
end

function M.check()
  start("review.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    local v = vim.version()
    ok(string.format("Neovim %d.%d.%d", v.major, v.minor, v.patch))
  else
    err("Neovim >= 0.9 is required")
  end

  if vim.fn.executable("git") == 1 then
    ok(vim.trim(vim.fn.system({ "git", "--version" })))
  else
    err("git not found in PATH")
  end

  local root = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and root[1] then
    ok("git repository: " .. root[1])
  else
    info("not inside a git repository (run :Review from one)")
  end

  check_codediff()

  if pcall(require, "nui.popup") then
    ok("nui.nvim")
  else
    err("nui.nvim not found", { "Install MunifTanjim/nui.nvim, the comment popup needs it" })
  end

  local export_cfg = require("review.config").get().export or {}
  if export_cfg.clipboard ~= false then
    if vim.fn.has("clipboard") == 1 then
      local provider = type(vim.g.clipboard) == "table" and vim.g.clipboard.name or nil
      ok("clipboard provider" .. (provider and (": " .. provider) or ""))
    else
      warn("no clipboard provider, exports won't reach the system clipboard", { "See :help clipboard, or set export.clipboard = false and use export.on_export" })
    end
  else
    info("export.clipboard is off")
  end
  if type(export_cfg.on_export) == "function" then
    info("export.on_export callback configured")
  end

  if pcall(require, "sidekick.cli") then
    ok("sidekick.nvim (optional)")
  else
    info("sidekick.nvim not installed (optional, for :Review sidekick)")
  end
end

return M
