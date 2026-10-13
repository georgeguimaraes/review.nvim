# Records assets/reviewed.gif with vhs 0.11 (https://github.com/charmbracelet/vhs).
# Run from the repo root: make demo
Output assets/reviewed.gif

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
Type "d=${TMPDIR:-/tmp}/review-reviewed-demo; assets/demo/make_reviewed_repo.sh $d && REVIEW_DEMO_DIR=$d XDG_DATA_HOME=$d-data nvim -u assets/demo/init.lua"
Enter
Sleep 1500ms
Show

Type ":Review"
Sleep 600ms
Enter
Sleep 2500ms

# r marks the file as reviewed and goes to the next unreviewed file
Type "r"
Sleep 2500ms
Type "r"
Sleep 2500ms

# <Tab> skips the reviewed files
Tab
Sleep 2000ms
Tab
Sleep 2500ms

# ]f still goes to every file, reviewed or not
Type "]f"
Sleep 1800ms
Type "]f"
Sleep 2500ms

# r on a reviewed file removes the mark
Type "r"
Sleep 3500ms
