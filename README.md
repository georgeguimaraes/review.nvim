# review.nvim

Code review annotations for codediff.nvim, optimized for AI feedback loops.

Inspired by [tuicr](https://github.com/agavra/tuicr).

## Features

- Add comments to specific lines in diff view (Note, Suggestion, Issue, Praise)
- Multi-line comment support with box-style virtual text display
- Comments displayed as signs, line highlights, and virtual text
- Comments persist per branch (stored in `~/.local/share/nvim/review/`)
- Auto-export comments to clipboard when closing
- Export comments to a project review file (default: `CODE_REVIEW.md`)
- Import existing review file on open to restore comments
- Export format optimized for AI conversations
- Send comments directly to [sidekick.nvim](https://github.com/folke/sidekick.nvim) for AI chat
- Commit picker modal to select specific commits to review
- Built on top of codediff.nvim

## Requirements

- Neovim >= 0.9
- [codediff.nvim](https://github.com/esmuellert/codediff.nvim)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)

## Installation

Using lazy.nvim:

```lua
{
  "georgeguimaraes/review.nvim",
  dependencies = {
    "esmuellert/codediff.nvim",
    "MunifTanjim/nui.nvim",
  },
  cmd = { "Review" },
  keys = {
    { "<leader>r", "<cmd>Review<cr>", desc = "Review" },
    { "<leader>R", "<cmd>Review commits<cr>", desc = "Review commits" },
  },
  opts = {},
}
```

## Usage

```vim
:Review              " Open codediff with comment keymaps (default)
:Review open         " Same as above
:Review commits      " Select commits to review (picker modal)
:Review close        " Close and export comments to clipboard
:Review export       " Export comments to clipboard
:Review preview      " Preview exported markdown in split
:Review write        " Write review markdown file
:Review write_close  " Write review file, copy to clipboard, and close
:Review sidekick     " Send comments to sidekick.nvim
:Review list         " List all comments
:Review clear        " Clear all comments
:Review toggle       " Toggle readonly/edit mode
```

## Keybindings (in diff view)

**Readonly mode** (default):
| Key | Action |
|-----|--------|
| `i` | Add comment (pick type from menu) |
| `d` | Delete comment at cursor |
| `e` | Edit comment at cursor |
| `c` | List all comments |
| `f` | Toggle file panel visibility |
| `R` | Toggle readonly/edit mode |
| `<Tab>` | Next file |
| `<S-Tab>` | Previous file |
| `]n` | Jump to next comment |
| `[n` | Jump to previous comment |
| `C` | Export to clipboard and show preview |
| `S` | Send comments to sidekick.nvim |
| `<C-r>` | Clear all comments |
| `q` | Close and export comments to clipboard |
| `w` | Write review file, copy to clipboard, and close |
| `W` | Write review file |

**Edit mode** (when `readonly = false`):
| Key | Action |
|-----|--------|
| `<leader>cn/cs/ci/cp` | Add Note/Suggestion/Issue/Praise |
| `<leader>cd` | Delete comment |
| `<leader>ce` | Edit comment |

**Comment popup** (when adding/editing):
| Key | Action |
|-----|--------|
| `Enter` | Insert newline (multi-line comments supported) |
| `Ctrl+s` | Submit comment |
| `Tab` | Cycle comment type |
| `Esc` / `q` | Cancel (normal mode) |

## Configuration

```lua
require("review").setup({
  comment_types = {
    note = { key = "n", name = "Note", icon = "📝", hl = "ReviewNote" },
    suggestion = { key = "s", name = "Suggestion", icon = "💡", hl = "ReviewSuggestion" },
    issue = { key = "i", name = "Issue", icon = "⚠️", hl = "ReviewIssue" },
    praise = { key = "p", name = "Praise", icon = "✨", hl = "ReviewPraise" },
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
  },
  export = {
    context_lines = 3,
    include_file_stats = true,
    file = {
      enabled = true,
      filename = "CODE_REVIEW.md",
      dir = ".",
      import_on_open = true,
    },
  },
  codediff = {
    readonly = true,
  },
})
```

## Export Format

Comments are exported as Markdown optimized for AI consumption. When writing to a file, each comment line includes a short inline marker (e.g. `<!--r:id=...-->`) so the plugin can restore comments on the next session without adding a large metadata block.

```markdown
I reviewed your code and have the following comments. Please address them.

Comment types: ISSUE (problems to fix), SUGGESTION (improvements), NOTE (observations), PRAISE (positive feedback)

1. **[ISSUE]** `src/components/Button.tsx:23` - Wrapping onClick creates a new function every render <!--r:id=comment_1700000000_1-->
2. **[SUGGESTION]** `src/utils/api.ts:45` - Consider using useMemo here <!--r:id=comment_1700000000_2-->
3. **[PRAISE]** `src/hooks/useAuth.ts:12` - Clean implementation of the auth flow <!--r:id=comment_1700000000_3-->
```

## Running Tests

```bash
make test
```

## License

Copyright 2025 George Guimarães

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
