if vim.g.loaded_review then
  return
end
vim.g.loaded_review = true

local subcommands = {
  open = { fn = function() require("review").open() end, desc = "Open codediff with review" },
  commits = { fn = function() require("review").open_commits() end, desc = "Select commits to review" },
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
    subcmd.fn()
  else
    vim.notify("Unknown subcommand: " .. cmd .. "\nAvailable: " .. table.concat(subcommand_names, ", "), vim.log.levels.ERROR, { title = "Review" })
  end
end, {
  nargs = "?",
  complete = function(arg_lead)
    return vim.tbl_filter(function(cmd)
      return cmd:find(arg_lead, 1, true) == 1
    end, subcommand_names)
  end,
  desc = "Review commands",
})
