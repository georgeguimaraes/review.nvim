# Records assets/demo.gif with vhs 0.11 (https://github.com/charmbracelet/vhs).
# Run from the repo root: make demo
Output assets/demo.gif

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
Type "d=${TMPDIR:-/tmp}/review-demo; assets/demo/make_repo.sh $d && REVIEW_DEMO_DIR=$d XDG_DATA_HOME=$d-data nvim -u assets/demo/init.lua"
Enter
Sleep 1500ms
Show

Type ":Review"
Sleep 600ms
Enter
Sleep 2500ms

# an issue on the new error handling
Type "9G"
Sleep 700ms
Type "i"
Sleep 900ms
Tab
Sleep 300ms
Tab
Sleep 500ms
Type "include the status code, callers will want it"
Sleep 700ms
Ctrl+S
Sleep 1500ms

# praise on the pcall
Type "15G"
Sleep 700ms
Type "i"
Sleep 900ms
Tab
Sleep 300ms
Tab
Sleep 300ms
Tab
Sleep 500ms
Type "nice, pcall around decode is the right call"
Sleep 700ms
Ctrl+S
Sleep 1500ms

# a suggestion on a range
Type "25G"
Sleep 500ms
Type "V"
Sleep 400ms
Type "2j"
Sleep 700ms
Type "i"
Sleep 900ms
Tab
Sleep 500ms
Type "upper-casing here feels like a view concern"
Sleep 700ms
Ctrl+S
Sleep 1800ms

# next file, a note
Tab
Sleep 1500ms
Type "4G"
Sleep 600ms
Type "i"
Sleep 900ms
Type "maybe return nil instead of an empty string?"
Sleep 700ms
Ctrl+S
Sleep 1800ms

# export: comments go to the clipboard as markdown, with a preview
Type "C"
Sleep 6000ms
