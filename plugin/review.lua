if vim.g.loaded_review then
  return
end
vim.g.loaded_review = true

local subcommands = {
  open = { fn = function() require("review").open() end, desc = "Open codediff with review" },
  commits = { fn = function(args) require("review").open_commits(args[1], args[2]) end, desc = "Select commits to review (optional: rev1 rev2)" },
  close = { fn = function() require("review").close() end, desc = "Close and export to clipboard" },
  export = { fn = function() require("review").export() end, desc = "Export comments to clipboard" },
  preview = { fn = function() require("review").preview() end, desc = "Preview exported markdown" },
  sidekick = { fn = function() require("review.export").to_sidekick() end, desc = "Send comments to sidekick.nvim" },
  clear = { fn = function() require("review").clear() end, desc = "Clear all comments" },
  list = { fn = function() require("review.comments").list() end, desc = "List all comments" },
  toggle = { fn = function() require("review").toggle_readonly() end, desc = "Toggle readonly/edit mode" },
}

local subcommand_names = vim.tbl_keys(subcommands)

vim.api.nvim_create_user_command("Review", function(opts)
  local args = opts.fargs
  local cmd = args[1]

  -- Default to "open" if no subcommand
  if not cmd or cmd == "" then
    cmd = "open"
  end

  local subcmd = subcommands[cmd]
  if subcmd then
    -- Pass remaining args to the subcommand
    local subargs = { unpack(args, 2) }
    subcmd.fn(subargs)
  else
    vim.notify("Unknown subcommand: " .. cmd .. "\nAvailable: " .. table.concat(subcommand_names, ", "), vim.log.levels.ERROR, { title = "Review" })
  end
end, {
  nargs = "*",
  complete = function(arg_lead, cmd_line)
    local parts = vim.split(cmd_line, "%s+", { trimempty = true })
    -- If still typing first arg (subcommand), complete subcommands
    if #parts <= 2 then
      return vim.tbl_filter(function(c)
        return c:find(arg_lead, 1, true) == 1
      end, subcommand_names)
    end
    return {}
  end,
  desc = "Review commands",
})
