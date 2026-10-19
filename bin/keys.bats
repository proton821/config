#!/usr/bin/env bats
# Tests for keys.sh. Run:  bats keys.bats (beside keys.sh)
# Minimal configs in a temp dir stand in for Neovim's, Ghostty's and Claude
# Code's; KEYS_OS picks the machine.
# shellcheck disable=SC2312  # the test idiom: assertions on what a command prints, and the fixtures and helpers they read through; a failure fails the assertion

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT=$BATS_TEST_DIRNAME/keys.sh
  # A copy without its x bit (the Mac's clone) runs as an executable copy.
  if [[ ! -x $SCRIPT ]]; then
    cp "$SCRIPT" "$BATS_TEST_TMPDIR/keys.sh"
    chmod +x "$BATS_TEST_TMPDIR/keys.sh"
    SCRIPT=$BATS_TEST_TMPDIR/keys.sh
  fi
  export NVIM_DIR=$BATS_TEST_TMPDIR/nvim GHOSTTY_CONF=$BATS_TEST_TMPDIR/ghostty
  export CLAUDE_SETTINGS=$BATS_TEST_TMPDIR/settings.json KEYS_OS=Linux
  mkdir -p "$NVIM_DIR/lua/config" "$NVIM_DIR/lua/plugins"
  echo '{ "extras": [ "lazyvim.plugins.extras.editor.neo-tree" ] }' >"$NVIM_DIR/lazyvim.json"
  printf '%s\n' 'font-size = 18' 'keybind = shift+enter=csi:13;2u' >"$GHOSTTY_CONF"
  echo '{"theme": "dark", "editorMode": "vim"}' >"$CLAUDE_SETTINGS"
}

@test "at most 80 wide, on either machine" {
  local os l
  for os in Linux Darwin; do
    KEYS_OS=$os run "$SCRIPT"
    [ "$status" -eq 0 ]
    for l in "${lines[@]}"; do [ "${#l}" -le 80 ]; done
  done
}

@test "one long list: the keyboard, then Neovim, Ghostty and Claude Code" {
  run "$SCRIPT"
  [[ ${lines[0]} == "KEYS  on the rig, Kinesis Advantage2" ]]
  [[ $output == *"KEYBOARD"*"NEOVIM: MOVE"*"NEOVIM: SEARCH AND FILES"*"GHOSTTY: TABS"*"CLAUDE CODE"* ]]
  [[ $output == *$'\n  h j k l        left down up right\n'* ]]
}

@test "the rig: the Kinesis keys and Ghostty's Linux keys" {
  run "$SCRIPT"
  [[ $output == *"the only Ctrl on the board"* ]]
  [[ $output == *$'\n  Ctrl+Shift+T   new tab\n'* && $output == *$'\n  Alt+1 .. 8     go to that tab\n'* ]]
  [[ $output == *$'\n  Super+C        copy the selection\n'* && $output == *"Lift's thumb keys"* ]]
  [[ $output != *"Cmd+"* ]]
}

@test "the Mac: its keyboards and Ghostty's macOS keys" {
  KEYS_OS=Darwin run "$SCRIPT"
  [[ ${lines[0]} == "KEYS  on the Mac, Logi Wave Keys or the MacBook keyboard" ]]
  [[ $output == *$'\n  Cmd+T          new tab\n'* && $output == *$'\n  Cmd+Shift+]    next tab\n'* ]]
  [[ $output == *$'\n  Cmd+C          copy the selection\n'* && $output == *"Cmd+G  Cmd+Shift+G"* ]]
  [[ $output != *"Kinesis"* && $output != *"Super"* && $output != *"Ctrl+Shift+T"* && $output != *"Lift"* ]]
}

@test "the Mac reads Ghostty's settings from the clone beside the script" {
  local clone=$BATS_TEST_TMPDIR/clone
  mkdir -p "$clone/bin" "$clone/.config/ghostty"
  cp "$SCRIPT" "$clone/bin/"
  echo 'keybind = shift+enter=csi:13;2u' >"$clone/.config/ghostty/mac"
  unset GHOSTTY_CONF
  KEYS_OS=Darwin run "$clone/bin/keys.sh"
  [[ $output != *"!!"* ]]
  rm "$clone/.config/ghostty/mac"
  KEYS_OS=Darwin run "$clone/bin/keys.sh"
  [[ $output == *"!! Ghostty no longer sends Shift+Enter"* ]]
}

@test "prose basics only: no code features" {
  run "$SCRIPT"
  [[ $output == *"x  r x         delete / replace a letter"* ]]
  [[ $output == *"u  Ctrl+R      undo / redo"* ]]
  [[ $output != *"gd "* && $output != *"formats"* ]]
}

@test "no escape codes when piped" {
  run "$SCRIPT"
  [[ $output != *$'\e'* ]]
}

@test "configs that match the sheet give no warning" {
  run "$SCRIPT"
  [[ $output != *"!!"* ]]
}

@test "neo-tree dropped from the extras is flagged" {
  echo '{ "extras": [] }' >"$NVIM_DIR/lazyvim.json"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "!! neo-tree is no longer enabled"* ]]
}

@test "a leader set in the config is flagged" {
  echo 'vim.g.mapleader = ","' >"$NVIM_DIR/lua/config/keymaps.lua"
  run "$SCRIPT"
  [[ $output == *"!! the config sets its own leader"* ]]
}

@test "Ghostty without the Shift+Enter key, or Claude Code out of vim mode, is flagged" {
  echo 'font-size = 18' >"$GHOSTTY_CONF"
  echo '{"theme": "dark"}' >"$CLAUDE_SETTINGS"
  run "$SCRIPT"
  [[ $output == *"!! Ghostty no longer sends Shift+Enter"* ]]
  [[ $output == *"!! Claude Code isn't in vim mode"* ]]
}

@test "arguments are refused" {
  run "$SCRIPT" refresh
  [ "$status" -eq 1 ]
  [[ $output == *"usage: keys.sh"* ]]
}
