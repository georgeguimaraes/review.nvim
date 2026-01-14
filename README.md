# diffnotes.nvim

Code review annotations for diffview.nvim, optimized for AI feedback loops.

## Features

- Add comments to specific lines in diff view (Note, Suggestion, Issue, Praise)
- Comments displayed as signs, line highlights, and virtual text
- Unified diff view by default (toggle with `t`)
- Comments persist per branch (stored in `~/.local/share/nvim/diffnotes/`)
- Auto-export comments to clipboard when closing
- Export format optimized for AI conversations
- Built on top of diffview.nvim

## Requirements

- Neovim >= 0.9
- [diffview.nvim](https://github.com/sindrets/diffview.nvim)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for tests)

## Installation

Using lazy.nvim:

```lua
{
  "your-username/diffnotes.nvim",
  dependencies = {
    "sindrets/diffview.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("diffnotes").setup()
  end,
}
```

## Usage

```vim
:DiffnotesOpen          " Open diffview with comment keymaps enabled
:DiffnotesExport        " Export comments to clipboard
:DiffnotesPreview       " Preview exported markdown in split
:DiffnotesList          " List all comments in quickfix
:DiffnotesClear         " Clear all comments
:DiffnotesToggleLayout  " Cycle layout (horizontal/vertical)
:DiffnotesClose         " Close diffview
```

## Keybindings (in diff view)

**Readonly mode** (default):
| Key | Action |
|-----|--------|
| `i` | Add comment (pick type from menu) |
| `d` | Delete comment at cursor |
| `e` | Edit comment at cursor |
| `c` | List all comments (quickfix) |
| `t` | Cycle layout (horizontal/vertical/single) |
| `f` | Toggle focus (file panel/content) |
| `R` | Toggle readonly/edit mode |
| `<Tab>` | Next file |
| `<S-Tab>` | Previous file |
| `]c` | Jump to next comment |
| `[c` | Jump to previous comment |
| `<C-e>` | Export comments to clipboard |
| `C` | Clear all comments |
| `q` | Close and copy comments to clipboard |

**Edit mode** (when `readonly = false`):
| Key | Action |
|-----|--------|
| `<leader>cn/cs/ci/cp` | Add Note/Suggestion/Issue/Praise |
| `<leader>cd` | Delete comment |
| `<leader>ce` | Edit comment |

## Configuration

```lua
require("diffnotes").setup({
  comment_types = {
    note = { key = "n", name = "Note", icon = "📝", hl = "DiffnotesNote" },
    suggestion = { key = "s", name = "Suggestion", icon = "💡", hl = "DiffnotesSuggestion" },
    issue = { key = "i", name = "Issue", icon = "⚠️", hl = "DiffnotesIssue" },
    praise = { key = "p", name = "Praise", icon = "✨", hl = "DiffnotesPraise" },
  },
  keymaps = {
    add_note = "<leader>cn",
    add_suggestion = "<leader>cs",
    add_issue = "<leader>ci",
    add_praise = "<leader>cp",
    delete_comment = "<leader>cd",
    edit_comment = "<leader>ce",
    next_comment = "]c",
    prev_comment = "[c",
    export = "<C-e>",
    toggle_layout = "<C-l>",
  },
  export = {
    context_lines = 3,
    include_file_stats = true,
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

## Running Tests

```bash
make test
```

## License

MIT
