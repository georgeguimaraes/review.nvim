# Records assets/notes.gif with vhs 0.11: notes on plain buffers, no diff open.
# Run from the repo root: make demo
Output assets/notes.gif

Set Shell zsh
Set FontFamily "VictorMono Nerd Font"
Set FontSize 15
Set Width 1300
Set Height 760
Set Padding 12
Set Framerate 24
# Tokyo Night (night) palette, matching the tokyonight-night colorscheme
Set Theme { "name": "Tokyo Night", "background": "#1a1b26", "foreground": "#c0caf5", "cursor": "#c0caf5", "selection": "#33467c", "black": "#15161e", "red": "#f7768e", "green": "#9ece6a", "yellow": "#e0af68", "blue": "#7aa2f7", "magenta": "#bb9af7", "cyan": "#7dcfff", "white": "#a9b1d6", "brightBlack": "#414868", "brightRed": "#f7768e", "brightGreen": "#9ece6a", "brightYellow": "#e0af68", "brightBlue": "#7aa2f7", "brightMagenta": "#bb9af7", "brightCyan": "#7dcfff", "brightWhite": "#c0caf5" }
Set TypingSpeed 40ms

Hide
Type "d=${TMPDIR:-/tmp}/review-demo; assets/demo/make_repo.sh $d && REVIEW_DEMO_DIR=$d XDG_DATA_HOME=$d-data nvim -u assets/demo/init.lua $d/src/api.lua"
Enter
Sleep 1500ms
Show

# a note while just reading the file, no diff open
Type "16G"
Sleep 800ms
Type ":Review note"
Sleep 500ms
Enter
Sleep 900ms
Type "swallowing the parse error hides bad payloads"
Sleep 700ms
Ctrl+S
Sleep 1800ms

# a range note from a visual selection
Type "22G"
Sleep 500ms
Type "V"
Sleep 400ms
Type "2j"
Sleep 700ms
Type ":"
Sleep 300ms
Type "Review note"
Sleep 500ms
Enter
Sleep 900ms
Tab
Sleep 500ms
Type "move the upper-casing to the caller"
Sleep 700ms
Ctrl+S
Sleep 1800ms

# another file, another note
Type ":e src/utils.lua"
Sleep 500ms
Enter
Sleep 1000ms
Type "4G"
Sleep 600ms
Type ":Review note"
Sleep 500ms
Enter
Sleep 900ms
Type "maybe return nil instead of an empty string?"
Sleep 700ms
Ctrl+S
Sleep 1800ms

# the notes are there when the review opens
Type ":Review"
Sleep 600ms
Enter
Sleep 3000ms

# and in the export
Type "C"
Sleep 5000ms
