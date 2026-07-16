alias ll='ls -al'
alias lt='ls -alrt'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gd='git diff'
alias gr='git restore'
alias grep='grep --color=auto'
alias cc='claude --continue'
alias cr='claude --resume'
alias ac='agy -c'
# md <file.md> — render markdown with glow in the pager, wrapped to the current
# terminal width. Uses bash's $COLUMNS (correct inside tmux), not `tput cols`,
# which reports 80 in a command substitution because its stdout is a pipe rather
# than the terminal. Falls back to 170 if $COLUMNS is somehow unset.
md() { glow -pn -w"${COLUMNS:-170}" "$@"; }

# monitor <file.md> [scan-depth] — live-render a markdown status table with
# glow, re-rendering on every change (Ctrl-C to stop). Same glow formatting as
# `md` (line numbers, wrapped to the current terminal width) minus the pager;
# matching the width to the terminal keeps table rows from soft-wrapping into
# extra screen lines. Shows the file's title/preamble plus the
# FIRST contiguous markdown table (whose first row appears within the top
# <scan-depth> lines, default 25) and stops where that table ends — so a second
# table further down is never shown. The awk finds the first `|`-line, prints
# the whole contiguous block however long, then exits at the line that ends it.
# glow only styles when its stdout is the terminal, so we feed the extracted
# lines on stdin and let glow render to the TTY (piping glow's *output* would
# strip styling). Polls mtime (1s): no deps, works on /mnt/c, and survives
# agents that rewrite the file via temp+rename.
monitor() {
    local file="$1" scan="${2:-25}" last="" now
    [ -z "$file" ] && { echo "usage: monitor <file.md> [scan-depth]" >&2; return 2; }
    [ -f "$file" ] || { echo "monitor: no such file: $file" >&2; return 1; }
    while true; do
        now=$(stat -c %Y "$file" 2>/dev/null) || now=""
        if [ -n "$now" ] && [ "$now" != "$last" ]; then
            clear
            awk -v max="$scan" 'NR>max && !t{exit} /^[[:space:]]*\|/{t=1;print;next} t{exit} {print}' "$file" | glow -n -w"${COLUMNS:-170}" -
            last="$now"
        fi
        sleep 1
    done
}
