# review.nvim

Code review annotations for codediff.nvim, optimized for AI feedback loops.

Inspired by [tuicr](https://github.com/agavra/tuicr).

## Features

- Add comments to specific lines in diff view (Note, Suggestion, Issue, Praise)
- Multi-line comment support with box-style virtual text display
- Comments displayed as signs, line highlights, and virtual text
- Comments persist per branch (stored in `~/.local/share/nvim/review/`)
- Auto-export comments to clipboard when closing
- Export format optimized for AI conversations
- Send comments directly to [sidekick.nvim](https://github.com/folke/sidekick.nvim) for AI chat
- Commit picker modal to select specific commits to review
- **GitHub PR review support**: checkout PRs, view existing comments, submit reviews
- Built on top of codediff.nvim

## Requirements

- Neovim >= 0.9
- [codediff.nvim](https://github.com/esmuellert/codediff.nvim)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- [GitHub CLI](https://cli.github.com/) (optional, for PR reviews)

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
:Review PR           " Review a GitHub PR (opens picker)
:Review PR 123       " Review specific PR by number
:Review submit       " Submit review to GitHub
:Review close        " Close and export comments to clipboard
:Review export       " Export comments to clipboard
:Review preview      " Preview exported markdown in split
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

**GitHub PR keymaps** (when reviewing a PR):
| Key | Action |
|-----|--------|
| `gC` | Show GitHub thread at cursor |
| `gn` | Start new GitHub thread at cursor |
| `gS` | Start GitHub suggestion (one-click apply) |
| `gn` (visual) | Multi-line comment on selection |
| `gS` (visual) | Multi-line suggestion on selection |
| `gp` | Show PR description |
| `]t` | Jump to next GitHub thread |
| `[t` | Jump to previous GitHub thread |
| `gs` | Submit review to GitHub |

**Thread popup keymaps** (when viewing a thread with `gC`):
| Key | Action |
|-----|--------|
| `r` | Reply to thread |
| `R` | Toggle resolved status |
| `e` | Edit your last comment |
| `d` | Delete your last comment |
| `+` | Add reaction to last comment |
| `q` | Close popup |

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
2. **[SUGGESTION]** `src/utils/api.ts:45` - Consider using useMemo here
3. **[PRAISE]** `src/hooks/useAuth.ts:12` - Clean implementation of the auth flow
```

## GitHub PR Review

review.nvim can review GitHub PRs directly. It uses the `gh` CLI to checkout PRs, fetch existing review threads, and submit reviews.

### Setup

1. Install [GitHub CLI](https://cli.github.com/)
2. Authenticate: `gh auth login`

### Workflow

```vim
:Review PR           " Pick from open PRs
:Review PR 123       " Open specific PR
```

This will:
1. Checkout the PR branch
2. Open codediff with the correct diff (merge-base to head)
3. Fetch and display existing GitHub review threads
4. Let you add your own annotations

### Viewing GitHub Threads

Existing PR comments show as purple `◆` signs (or gray `✓` if resolved). Press `gC` to view the full thread with all replies and reactions. From the thread popup you can reply, resolve/unresolve, edit or delete your comments, and add reactions.

### Multi-line Comments

Select lines in visual mode, then press `gn` for a multi-line comment or `gS` for a multi-line suggestion. GitHub will highlight the entire range in the PR.

### Submitting Reviews

After adding your annotations, press `gs` or run `:Review submit`:

1. Preview your comments
2. Choose review type: Approve (`a`), Comment (`c`), or Request Changes (`r`)
3. Add an optional summary
4. Comments are submitted as a PR review

Your local comment types map to GitHub:
- **Issue** → suggests "Request Changes"
- **Suggestion/Note** → suggests "Comment"
- **Praise** → suggests "Approve"

## Running Tests

```bash
make test
```

## License

Copyright 2025 George Guimarães

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
