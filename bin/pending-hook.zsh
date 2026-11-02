# pending-hook.zsh - when you run a command from pending.txt, exactly as
# written there, it runs through `pending.sh run` instead: the same command,
# its output on screen and kept for Claude in ~/.local/state/pending/, the
# job marked "ran ...: ok" or "failed (exit N)", and a failure ending with
# "ERROR: ...". Every other line runs as normal, untouched.
#
# How: zsh can't skip a command from preexec, so a line-finish widget hook
# (Enter) looks at the whole line, less the blanks at its ends and a trailing
# newline (a line copied whole, as Neovim's yy does, and pasted brings it),
# and less any "#" lines, so a job pasted whole is its one command (zsh would
# try to run its "#" lines, without interactivecomments): only when one line
# is left, in pending.txt, and `pending.sh match` calls it a job's command does
# it turn the line into `pending-run 'LINE'`, which shows on screen as it
# runs. History keeps the line as typed (zshaddhistory), and $? afterwards
# is the command's. Two commands pasted together are never a job's.
#
# Each new shell runs `pending.sh tidy` in the background, so lines a hand cut
# left with no job go with no one asking.
#
# pending.sh runs through the bash on PATH (Homebrew's on the Mac), since
# the Mac's clone keeps no x bit. Not for scripts: only interactive shells,
# and only if pending.sh is beside it. zsh, not bash, so ShellCheck can't
# read it. One line install.sh puts in ~/.zshrc loads it. Tests:
# pending-hook.bats.

[[ -o interactive ]] || return 0

typeset -g __pending_cmd=${${(%):-%x}:A:h}/pending.sh
[[ -r $__pending_cmd ]] || return 0
typeset -g __pending_line=
# pending.txt, where pending.sh finds it (~/x/pending.txt on the Mac,
# ~/pending.txt on the rig), read here: inside a widget $PENDING is zle's
# own (how many keys wait).
if [[ $OSTYPE == darwin* ]]; then
  typeset -g __pending_file=${PENDING:-$HOME/x/pending.txt}
else
  typeset -g __pending_file=${PENDING:-$HOME/pending.txt}
fi

# __pending_finish: the line-finish hook; turns a job's command line
# into a pending-run of it.
__pending_finish() {
  local l line= kept=0
  [[ -n $BUFFER ]] || return 0
  for l in "${(@f)BUFFER}"; do
    while [[ $l == [[:space:]]* ]]; do l=${l#?}; done
    while [[ $l == *[[:space:]] ]]; do l=${l%?}; done
    [[ -n $l && $l != \#* ]] || continue
    line=$l
    kept=$((kept + 1))
  done
  (( kept == 1 )) || return 0
  command grep -Fqx -- "$line" "$__pending_file" 2>/dev/null || return 0
  command env PENDING="$__pending_file" bash -- "$__pending_cmd" match "$line" \
    >/dev/null 2>&1 || return 0
  __pending_line=$BUFFER
  BUFFER="pending-run ${(q-)line}"
}

# zshaddhistory: the line as typed goes into history, not its pending-run.
__pending_history() {
  [[ -n $__pending_line && ${1%$'\n'} == "pending-run "* ]] || return 0
  print -s -- "${__pending_line%$'\n'}"
  __pending_line=
  return 1
}

# pending-run LINE: LINE through `pending.sh run`; returns as LINE did. A
# line no longer in pending.txt (removed in between), or whose log can't be
# kept, runs nothing: run it again.
pending-run() {
  local rc=0
  PENDING=$__pending_file command bash -- "$__pending_cmd" run "$1" || rc=$?
  if (( rc == 100 )); then
    print -u2 -- "pending: no longer in pending.txt or no log kept, nothing ran; run it again"
  fi
  return $rc
}

# Loaded from .zshrc, before zle is: load it now, or the widget hook is
# silently not added.
zmodload zsh/zle || return 0
autoload -Uz add-zle-hook-widget add-zsh-hook
add-zle-hook-widget line-finish __pending_finish
add-zsh-hook zshaddhistory __pending_history
( PENDING=$__pending_file command bash -- "$__pending_cmd" tidy </dev/null >/dev/null 2>&1 &! )
