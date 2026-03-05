# review.nvim 🧐

Code review annotations for codediff.nvim, optimized for AI feedback loops.

Inspired by [tuicr](https://github.com/agavra/tuicr).

## Features

- Add comments to specific lines in diff view (Note, Suggestion, Issue, Praise)
- Multi-line comment support with box-style virtual text display
- Comments displayed as signs, line highlights, and virtual text
- Comments persist per branch (stored in Neovim's XDG data directory: `~/.local/share/nvim/review/`)
- Auto-export comments to clipboard when closing
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
:Review commits SHA  " Review a single commit (diffs SHA^ against SHA)
:Review commits REV1 REV2  " Review specific revision range (skips picker)
:Review close        " Close and export comments to clipboard
:Review export       " Export comments to clipboard
:Review preview      " Preview exported markdown in split
:Review sidekick     " Send comments to sidekick.nvim
:Review list         " List all comments
:Review clear        " Clear all comments
:Review toggle       " Toggle readonly/edit mode
```

## Workflow

Open a review with `:Review` to see your staged and unstaged changes in a side-by-side diff, or `:Review commits` if you want to pick specific commits to review. The diff opens in a new tab with a file panel on the left.

Navigate between files with `<Tab>` and `<S-Tab>`. Toggle the file panel with `f`. Press `t` to toggle between side-by-side and inline layout. Switch between the old (left) and new (right) panes with `<C-w>h` and `<C-w>l`. When you spot something worth commenting on, press `i` on the line and pick a comment type from the menu (note, suggestion, issue, praise). The comment renders inline as a box below the line with a sign icon in the gutter.

For multi-line comments, visually select the range first then press `i`. For file-level comments that apply to the whole file, press `F`. Comments on the left (old) side of the diff only show on that side, and same for the right (new) side.

Use `]n` and `[n` to jump between comments, `e` to edit one, `d` to delete. Press `c` to see a list of all comments across files and jump to any of them.

When you're done, press `q` to close the review. This automatically copies all your comments to the clipboard as structured markdown and shows a preview. Paste it into Claude Code, sidekick.nvim (`S`), or wherever you're chatting with an AI. The format looks like this:

```
1. **[ISSUE]** `src/api.ts:23` - This endpoint doesn't handle errors
2. **[SUGGESTION]** `src/utils.ts:~10` - The old implementation was cleaner
```

Lines prefixed with `~` refer to the old (left) side of the diff. Comments persist per branch, so you can close Neovim and come back to the same review later. Sessions auto-expire after 7 days.

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
| `t` | Toggle side-by-side/inline layout |
| `g?` | Show codediff help |

**Edit mode** (when `readonly = false`):
| Key | Action |
|-----|--------|
| `<localleader>cn/cs/ci/cp` | Add Note/Suggestion/Issue/Praise |
| `<localleader>cd` | Delete comment |
| `<localleader>ce` | Edit comment |

**Comment popup** (when adding/editing):
| Key | Action |
|-----|--------|
| `Enter` | Insert newline (multi-line comments supported) |
| `Ctrl+s` | Submit comment |
| `Tab` | Cycle comment type |
| `Esc` / `q` | Cancel (normal mode) |

## Configuration

All keymaps can be set to `false` to disable them.

**Keymap options**
| Option | Default | Action |
|--------|---------|--------|
| `add_note` | `<leader>cn` | Add note (edit mode) |
| `add_suggestion` | `<leader>cs` | Add suggestion (edit mode) |
| `add_issue` | `<leader>ci` | Add issue (edit mode) |
| `add_praise` | `<leader>cp` | Add praise (edit mode) |
| `delete_comment` | `<leader>cd` | Delete comment (edit mode) |
| `edit_comment` | `<leader>ce` | Edit comment (edit mode) |
| `next_comment` | `]n` | Next comment |
| `prev_comment` | `[n` | Previous comment |
| `next_file` | `<Tab>` | Next file |
| `prev_file` | `<S-Tab>` | Previous file |
| `toggle_file_panel` | `f` | Toggle file panel |
| `list_comments` | `c` | List all comments |
| `export_clipboard` | `C` | Export to clipboard |
| `send_sidekick` | `S` | Send comments to sidekick |
| `clear_comments` | `<C-r>` | Clear all comments |
| `close` | `q` | Close and export |
| `toggle_readonly` | `R` | Toggle readonly/edit mode |
| `readonly_add` | `i` | Add comment (readonly mode) |
| `readonly_delete` | `d` | Delete comment (readonly mode) |
| `readonly_edit` | `e` | Edit comment (readonly mode) |
| `popup_submit` | `<C-s>` | Submit comment (popup, insert & normal) |
| `popup_cancel` | `q` | Cancel comment (popup, normal mode) |
| `popup_cycle_type` | `<Tab>` | Cycle comment type (popup) |

```lua
require("review").setup({
  comment_types = {
    note = { key = "n", name = "Note", icon = "📝", hl = "ReviewNote" },
    suggestion = { key = "s", name = "Suggestion", icon = "💡", hl = "ReviewSuggestion" },
    issue = { key = "i", name = "Issue", icon = "⚠️", hl = "ReviewIssue" },
    praise = { key = "p", name = "Praise", icon = "✨", hl = "ReviewPraise" },
  },
  keymaps = {
    add_note = "<localleader>cn",
    add_suggestion = "<localleader>cs",
    add_issue = "<localleader>ci",
    add_praise = "<localleader>cp",
    delete_comment = "<localleader>cd",
    edit_comment = "<localleader>ce",
    next_comment = "]n",
    prev_comment = "[n",
    toggle_file_panel = "f",
  },
  codediff = {
    readonly = true,
  },
})
```

## Export Format

Comments are exported as Markdown optimized for AI consumption:

```markdown
I reviewed your code and have the following comments. Please address them.

Comment types: ISSUE (problems to fix), SUGGESTION (improvements), NOTE (observations), PRAISE (positive feedback)

1. **[ISSUE]** `src/components/Button.tsx:23` - Wrapping onClick creates a new function every render
2. **[SUGGESTION]** `src/utils/api.ts:~45` - The old implementation was cleaner
3. **[PRAISE]** `src/hooks/useAuth.ts:12-18` - Clean implementation of the auth flow
```

Lines prefixed with `~` (e.g. `:~45`) refer to the old (left) side of the diff. Range comments use `start-end` notation.

## Running Tests

```bash
make test
```

## License

Copyright 2025 George Guimarães

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
