#!/usr/bin/env bash
# keys.sh - the cheat sheet of the keys used on both machines: the rig
# (Omarchy, a Kinesis Advantage2 in Mac thumb mode) and the work Mac (a Logi
# Wave Keys, or the MacBook's own keyboard). One long list: the keyboard,
# then Neovim (LazyVim; basics for writing prose), Ghostty (tabs, copy and
# paste, search) and Claude Code (vim mode). Each machine gets its own keys,
# from uname. The lines that depend on a config are checked against it, and
# a "!!" line at the top says when one no longer holds. Runs on macOS's own
# bash 3.2 too.
#
# Usage:
#   keys.sh            print the cheat sheet
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OS=${KEYS_OS:-$(uname -s)}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
NVIM_DIR=${NVIM_DIR:-$CONFIG_HOME/nvim}
CLAUDE_SETTINGS=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
# Ghostty's settings: the rig's own config; on the Mac, the clone's file
# beside this script's bin/.
if [[ $OS == Darwin ]]; then GHOSTTY_CONF=${GHOSTTY_CONF:-$HERE/../.config/ghostty/mac}
else GHOSTTY_CONF=${GHOSTTY_CONF:-$CONFIG_HOME/ghostty/config}; fi

die() { printf 'keys: %s\n' "$*" >&2; exit 1; }
(($# == 0)) || die "usage: keys.sh (no arguments)"

# Bold headings only on a terminal.
B='' R=''
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then B=$'\e[1m' R=$'\e[0m'; fi

# drift: a "!!" line for each sheet line the configs no longer back.
drift() {
  grep -qs 'extras.editor.neo-tree' "$NVIM_DIR/lazyvim.json" \
    || echo '!! neo-tree is no longer enabled: the Space e line is out of date'
  if grep -rqs 'mapleader' "$NVIM_DIR/lua"; then
    echo '!! the config sets its own leader: the sheet assumes Space'
  fi
  grep -qsE '^keybind *= *shift\+enter=csi:13;2u' "$GHOSTTY_CONF" \
    || echo "!! Ghostty no longer sends Shift+Enter as CSI u: Claude Code's new line"
  grep -qsE '"editorMode": *"vim"' "$CLAUDE_SETTINGS" \
    || echo "!! Claude Code isn't in vim mode: its Esc line is out of date"
}

head_() { printf '\n%s%s%s\n' "$B" "$1" "$R"; }
# key KEY DESC: one line, the key padded to 15.
key() { printf '  %-15s%s\n' "$1" "$2"; }

if [[ $OS == Darwin ]]; then
  MACHINE='the Mac, Logi Wave Keys or the MacBook keyboard'
  TAB_NEW=Cmd+T TAB_CLOSE=Cmd+W TAB_NEXT='Cmd+Shift+]' TAB_PREV='Cmd+Shift+['
  TAB_N='Cmd+1 .. 8' TAB_LAST=Cmd+9 COPY=Cmd+C PASTE=Cmd+V FIND=Cmd+F
else
  MACHINE='the rig, Kinesis Advantage2'
  TAB_NEW=Ctrl+Shift+T TAB_CLOSE=Ctrl+Shift+W TAB_NEXT=Ctrl+Tab TAB_PREV=Ctrl+Shift+Tab
  TAB_N='Alt+1 .. 8' TAB_LAST=Alt+9 COPY=Super+C PASTE=Super+V FIND=Ctrl+Shift+F
fi

drift
printf '%sKEYS%s  on %s\n' "$B" "$R" "$MACHINE"

head_ KEYBOARD
if [[ $OS == Darwin ]]; then
  key Esc    'top left: back to Normal mode after every edit'
  key Ctrl   'control: every Ctrl key below (Cmd never stands in for it)'
  key Cmd    'beside Space: Ghostty'"'"'s tabs, copy and paste'
  key Space  'Neovim'"'"'s leader key. Hold it a moment: every Space key, listed'
else
  key Esc    'small key far top left: back to Normal mode after every edit'
  key Space  'right thumb, big key: the leader; hold it: every Space key'
  key Ctrl   'right thumb, small key above PgUp (the only Ctrl on the board)'
  key Super  'the outer top thumb keys: Hyprland'"'"'s, and copy and paste'
fi

head_ 'NEOVIM: MOVE'
key 'h j k l'   'left down up right'
key 'w  b'      'next / previous word'
key e           'end of word'
key '0  $'      'start / end of line'
key 'gg  G'     'top / bottom of file'
key 'f x'       'onto the next x on the line'
key 'Ctrl+D/U'  'half a page down / up'

head_ 'NEOVIM: WRITE'
key 'i  a'      'insert / append'
key A           'append at end of line'
key 'o  O'      'new line below / above'
key R           'overwrite until Esc'

head_ 'NEOVIM: FIX'
key 'x  r x'    'delete / replace a letter'
key dd          'cut the line'
key 'dw  d$'    'cut to next word / to the end'
key 'cw  c$'    'change to next word / to the end'
key ciw         'change the whole word'
key 'u  Ctrl+R' 'undo / redo'
key .           'repeat the last change'

head_ 'NEOVIM: COPY AND PASTE'
key 'yy  yw'    'copy the line / to next word'
key 'v  V'      'select letters / lines, then y or d: copy / cut'
key 'p  P'      'paste after / before'
key ''          'y and p use the system clipboard (d and x fill it too)'

head_ 'NEOVIM: SEARCH AND FILES'
key '/word Enter' 'search forward; n  N: next / previous match'
key ':%s/a/b/g' 'then Enter: every a to b'
key 'Space Space' 'find a file'
key 'Space e'   'file tree (Neo-tree)'
key Ctrl+S      'save (in insert too)'
key 'Shift+H / L' 'previous / next file'
key 'Space q q' 'quit everything'

head_ 'GHOSTTY: TABS'
key "$TAB_NEW"  'new tab'
key "$TAB_CLOSE" 'close the tab'
key "$TAB_NEXT" 'next tab'
key "$TAB_PREV" 'previous tab'
key "$TAB_N"    'go to that tab'
key "$TAB_LAST" 'the last tab'

head_ 'GHOSTTY: COPY, PASTE, SEARCH'
key "$COPY"     'copy the selection'
key "$PASTE"    'paste'
if [[ $OS == Darwin ]]; then
  key "$FIND"   'search the scrollback; Cmd+G  Cmd+Shift+G: next / previous'
else
  key "$FIND"   'search the scrollback'
  key ''        'the Lift'"'"'s thumb keys: rear copies, front pastes'
fi
key Esc         'end the search'

head_ 'CLAUDE CODE'
key Enter       'send the prompt'
key Shift+Enter 'new line in the prompt'
key Esc         'in the prompt: Normal mode (vim keys, as in Neovim)'
key Ctrl+C      'interrupt Claude; on an empty prompt, twice: quit'
key 'Esc Esc'   'on an empty prompt: rewind to an earlier point'
key Shift+Tab   'next permission mode (manual, accept edits, plan)'
key 'Up  Ctrl+R' 'an earlier prompt / search earlier prompts'
key Ctrl+G      'edit the prompt in your editor'
key Ctrl+S      'stash the prompt; again, on an empty prompt: back'
key Ctrl+V      'paste an image'
key Ctrl+O      'the transcript: every tool call'
key Ctrl+B      'send a running command or agent to the background'
key '/  !  @'   'a command or skill / a shell command / a file'
key '?'         'on an empty prompt: every key, listed'
