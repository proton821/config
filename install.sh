#!/usr/bin/env bash
# install.sh - put this repo's look and feel in place on the Mac: Neovim's
# config (Neovide's settings are in it), herdr's config, Ghostty's colours,
# Claude Code's theme and its shared rules (herdr draws in the terminal's
# colours, so it follows Ghostty's). The repo is published one way from
# another machine: nothing is edited here, and update discards any change
# made in this copy.
#
# Usage (the Mac's setup clones the repo, then runs this):
#   bash install.sh          link the configs, include Ghostty's settings,
#                            select Claude Code's theme, import the shared
#                            rules
#   bash install.sh update   fetch the published copy, list the commits and
#                            files it brings, and reset this one to it,
#                            listing each change, commit or added file it
#                            discards; then install
#   bash install.sh status   what is in place (no network)
#
# A config already there that isn't this repo's is moved aside to
# NAME.before-config (NAME.before-config.2 and on, if that is taken), with
# the plugins an earlier Neovim config installed; a link into another clone
# of this repo is replaced. The Mac's own files (Claude Code's settings and
# CLAUDE.md, Ghostty's config) are edited in place: a link stays a link and
# a file keeps its permissions.
# Written for macOS's own bash 3.2 and BSD tools.
set -euo pipefail

REPO=$(cd -P -- "$(dirname -- "$0")" >/dev/null && pwd -P)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
# Neovim's plugins, as lazy.nvim installs them.
LAZY=${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy
CLAUDE_SETTINGS=${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
# The shared rules are imported by one line of Claude Code's own CLAUDE.md;
# the rest of that file is the Mac's. A space in the path is escaped.
CLAUDE_MD=${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}
RULES_LINE=@$(printf '%s' "$REPO/claude-rules.md" | sed 's/ /\\ /g')
# Ghostty reads its legacy config, then config.ghostty, then the same two in
# Application Support, later ones winning, and the files their config-file
# lines include after all four. config.ghostty gets one line including the
# repo's Mac settings ("?": no error if the clone has gone), so they win over
# the four; a theme in a file included later, or colours set anywhere, win
# over them.
GHOSTTY_THEME=omarchy
GHOSTTY_MAC=.config/ghostty/mac
GHOSTTY_LINE="config-file = ?\"$REPO/$GHOSTTY_MAC\""
GHOSTTY_CONFIG=$CONFIG_HOME/ghostty/config.ghostty
GHOSTTY_BEFORE=$CONFIG_HOME/ghostty/config
GHOSTTY_SUPPORT="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_COLOURS='background|foreground|palette|cursor-color|cursor-text|selection-background|selection-foreground'
# What Neovim's config needs on PATH (README.md, "Needs").
NEEDS=${NEEDS:-nvim tree-sitter rg}

say()    { printf '%s\n' "$*"; }
ok()     { printf '  [ ok ] %s\n' "$*"; }
todo()   { printf '  [ -- ] %s\n' "$*"; }
die()    { printf '  [ !! ] %s\n' "$*" >&2; exit 1; }
indent() { sed 's/^/    /'; }

# The links: where each goes, then what it points to in the repo.
links() {
  printf '%s\t%s\n' "$CONFIG_HOME/nvim" .config/nvim
  printf '%s\t%s\n' "$CONFIG_HOME/herdr/config.toml" .config/herdr/config.toml
  printf '%s\t%s\n' "$CONFIG_HOME/ghostty/themes/$GHOSTTY_THEME" ".config/ghostty/themes/$GHOSTTY_THEME"
  printf '%s\t%s\n' "$HOME/.claude/themes/omarchy.json" .claude/themes/omarchy.json
}

linked() { [ -L "$1" ] && [ "$(readlink "$1")" = "$REPO/$2" ]; }   # TARGET FROM

a_clone() { [ -f "$1/install.sh" ] && [ -d "$1/.config/nvim" ]; }   # DIR: a clone of this repo

# old_link TARGET FROM: TARGET links to FROM in another clone of this repo.
old_link() {
  local to
  [ -L "$1" ] || return 1
  to=$(readlink "$1")
  case $to in /*"/$2") a_clone "${to%"/$2"}" ;; *) return 1 ;; esac
}

# aside PATH: moved to the first free PATH.before-config(.N), never over one.
aside() {
  local to=$1.before-config n=1
  while [ -e "$to" ] || [ -L "$to" ]; do n=$((n + 1)); to=$1.before-config.$n; done
  mv "$1" "$to"
  ok "moved the old one aside: $to"
}

link() {   # TARGET FROM
  local target=$1 src=$REPO/$2
  [ -e "$src" ] || die "the repo has no $2"
  if linked "$target" "$2"; then ok "$target"; return; fi
  if old_link "$target" "$2"; then rm "$target"
  elif [ -e "$target" ] || [ -L "$target" ]; then aside "$target"; fi
  mkdir -p "$(dirname "$target")"
  ln -s "$src" "$target"
  ok "$target -> $src"
}

# write_over FILE: FILE.new's text into FILE, through a link and keeping its
# permissions; then FILE.new goes.
write_over() { cat "$1.new" >"$1"; rm -f "$1.new"; }

needs() {
  local c missing=''
  for c in $NEEDS; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
  if [ -n "$missing" ]; then todo "not on PATH (README.md, \"Needs\"):$missing"
  else ok "on PATH: $NEEDS"; fi
}

# theme_ok: Claude Code's settings already hold every key of the repo's.
theme_ok() {
  [ -f "$CLAUDE_SETTINGS" ] || return 1
  jq -e --slurpfile want "$REPO/claude-settings.json" \
    '. as $have | $want[0] | to_entries | all(.value == $have[.key])' \
    "$CLAUDE_SETTINGS" >/dev/null 2>&1
}

claude() {
  local theme
  theme=$(jq -r .theme "$REPO/claude-settings.json")
  if theme_ok; then ok "Claude Code's theme"; return; fi
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  if [ -s "$CLAUDE_SETTINGS" ]; then
    # Only the repo's keys change; everything else in the file stays.
    if ! jq -s --slurpfile want "$REPO/claude-settings.json" \
           'if length == 1 and (.[0] | type) == "object" then .[0] * $want[0] else error("not one object") end' \
           "$CLAUDE_SETTINGS" >"$CLAUDE_SETTINGS.new" 2>/dev/null; then
      rm -f "$CLAUDE_SETTINGS.new"
      todo "Claude Code's theme: $CLAUDE_SETTINGS isn't one JSON object to merge into; set \"theme\": \"$theme\" in it"
      return
    fi
  else
    cp "$REPO/claude-settings.json" "$CLAUDE_SETTINGS.new"
  fi
  write_over "$CLAUDE_SETTINGS"
  ok "Claude Code's theme: $theme"
}

# ours LINE: LINE imports claude-rules.md from this repo or another clone of
# it (an older one); any other line is the Mac's own.
ours() {
  local path=${1%$'\r'}
  case $path in @/*/claude-rules.md) ;; *) return 1 ;; esac
  path=$(printf '%s' "${path#@}" | sed 's/\\ / /g')
  a_clone "$(dirname "$path")"
}

rules_ok() { [ -f "$CLAUDE_MD" ] && grep -qxF "$RULES_LINE" "$CLAUDE_MD"; }

rules() {
  local line
  if rules_ok; then ok "Claude Code's shared rules"; return; fi
  mkdir -p "$(dirname "$CLAUDE_MD")"
  # Only the import line changes (an older clone's goes).
  { if [ -f "$CLAUDE_MD" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        ours "$line" || printf '%s\n' "$line"
      done <"$CLAUDE_MD"
    fi
    printf '%s\n' "$RULES_LINE"; } >"$CLAUDE_MD.new"
  write_over "$CLAUDE_MD"
  ok "Claude Code's shared rules: imported in $CLAUDE_MD"
}

# ghostty_ok: config.ghostty includes this repo's Mac settings.
ghostty_ok() { [ -f "$GHOSTTY_CONFIG" ] && grep -qxF "$GHOSTTY_LINE" "$GHOSTTY_CONFIG"; }

# include_path DIR VALUE: the file a config-file line names, in a config
# file in DIR.
include_path() {
  local inc=$2
  inc=${inc#\?}; inc=${inc#\"}; inc=${inc%\"}
  case $inc in \~/*) inc=$HOME/${inc#\~/} ;; /*) ;; *) inc=$1/$inc ;; esac
  printf '%s\n' "$inc"
}

# includes FILE: the files FILE's config-file lines name, one a line.
includes() {
  local inc
  sed -n 's/^[[:space:]]*config-file[[:space:]]*=[[:space:]]*//p' "$1" |
    while IFS= read -r inc; do include_path "$(dirname "$1")" "$inc"; done
}

# ghostty_ours PATH: PATH is the Mac settings of this repo or another clone.
ghostty_ours() {
  case $1 in */"$GHOSTTY_MAC") a_clone "${1%"/$GHOSTTY_MAC"}" ;; *) return 1 ;; esac
}

# ghostty_sets FILE: FILE sets colours, or a file it includes (not this
# repo's) sets a theme or colours, which win over the repo's settings.
ghostty_sets() {
  local inc
  [ -f "$1" ] || return 1
  grep -Eq "^[[:space:]]*($GHOSTTY_COLOURS)[[:space:]]*=" "$1" && return 0
  includes "$1" | {
    while IFS= read -r inc; do
      ghostty_ours "$inc" && continue
      if [ -f "$inc" ] && grep -Eq "^[[:space:]]*(theme|$GHOSTTY_COLOURS)[[:space:]]*=" "$inc"; then exit 0; fi
    done
    exit 1
  }
}

# ghostty_overridden: the config files whose theme or colours win over the
# repo's, one a line.
ghostty_overridden() {
  local f
  for f in "$GHOSTTY_BEFORE" "$GHOSTTY_CONFIG" "$GHOSTTY_SUPPORT/config" "$GHOSTTY_SUPPORT/config.ghostty"; do
    if ghostty_sets "$f"; then printf '%s\n' "$f"; fi
  done
}

ghostty() {
  local line value over dir
  dir=$(dirname "$GHOSTTY_CONFIG")
  if ghostty_ok; then
    ok "Ghostty's settings"
  else
    mkdir -p "$dir"
    # Only the include line changes (an older clone's goes); everything else
    # in the file stays.
    { if [ -f "$GHOSTTY_CONFIG" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
          value=$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*config-file[[:space:]]*=[[:space:]]*//p')
          if [ -n "$value" ] && ghostty_ours "$(include_path "$dir" "$value")"; then continue; fi
          printf '%s\n' "$line"
        done <"$GHOSTTY_CONFIG"
      fi
      printf '%s\n' "$GHOSTTY_LINE"; } >"$GHOSTTY_CONFIG.new"
    write_over "$GHOSTTY_CONFIG"
    ok "Ghostty's settings: theme $GHOSTTY_THEME, left Option as Alt, herdr's tab keys (reload Ghostty's config to see them)"
  fi
  over=$(ghostty_overridden)
  if [ -n "$over" ]; then
    todo "these set colours, or include a theme, which win over this repo's: remove those lines"
    printf '%s\n' "$over" | indent
  fi
}

# plugins_off: Neovim's plugins installed at another commit than
# lazy-lock.json pins, one a line (one not installed, yet or at all, isn't).
plugins_off() {
  local lock=$REPO/.config/nvim/lazy-lock.json name commit
  command -v jq >/dev/null 2>&1 && [ -f "$lock" ] && [ -d "$LAZY" ] || return 0
  jq -r 'to_entries[] | "\(.key)\t\(.value.commit)"' "$lock" |
    while IFS="$(printf '\t')" read -r name commit; do
      [ -e "$LAZY/$name/.git" ] || continue
      if [ "$(git -C "$LAZY/$name" rev-parse -q --verify HEAD || true)" != "$commit" ]; then printf '%s\n' "$name"; fi
    done
}

plugins() {
  local off
  [ -d "$LAZY" ] || return 0
  off=$(plugins_off)
  if [ -z "$off" ]; then ok "Neovim's plugins at the commits lazy-lock.json pins"; return; fi
  todo "Neovim's plugins not at the commits lazy-lock.json pins (in Neovim, :Lazy restore fetches them):"
  printf '%s\n' "$off" | indent
}

# changes: what this copy has that the published one doesn't, one a line:
# changed and added files, then commits.
changes() {
  git -C "$REPO" status --porcelain
  git -C "$REPO" log --format='commit %h %s' origin/main..HEAD 2>/dev/null || true
}

cmd_install() {
  command -v jq >/dev/null 2>&1 || die "jq is needed (macOS 15 has it at /usr/bin/jq)"
  say "Installing from $REPO:"
  needs
  # Plugins an earlier config installed stay at their own commits: they go
  # aside with it, so Neovim's first start installs each at its pin.
  if ! linked "$CONFIG_HOME/nvim" .config/nvim && { [ -e "$LAZY" ] || [ -L "$LAZY" ]; }; then aside "$LAZY"; fi
  local target from
  while IFS="$(printf '\t')" read -r target from; do link "$target" "$from"; done <<EOF
$(links)
EOF
  ghostty
  claude
  rules
  plugins
}

cmd_update() {
  local changed incoming
  # Before the fetch, so the commits listed are this copy's own.
  changed=$(changes)
  # A public repo: no credential is offered, and none is asked for. The
  # Mac's own git config is left out, so nothing in it (an insteadOf, a
  # credential helper) can send the fetch elsewhere or offer a work key.
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    git -C "$REPO" -c credential.helper= fetch -q origin
  # What Neovim and Claude Code will load, to read before using them.
  incoming=$(git -C "$REPO" log --stat --format='commit %h %s' HEAD..origin/main)
  if [ -n "$incoming" ]; then
    say "Taking from the published copy:"
    printf '%s\n' "$incoming" | indent
  else
    ok "nothing new published"
  fi
  if [ -n "$changed" ]; then
    say "Discarding changes made in this copy (make them at the source):"
    printf '%s\n' "$changed" | indent
  fi
  git -C "$REPO" checkout -q -f -B main origin/main
  git -C "$REPO" clean -q -fd
  ok "at $(git -C "$REPO" log -1 --format='%h: %s')"
  # The new copy's own script installs: it may have changed.
  exec bash "$REPO/install.sh"
}

cmd_status() {
  local target from changed
  say "$REPO, at $(git -C "$REPO" log -1 --format='%h: %s'):"
  needs
  while IFS="$(printf '\t')" read -r target from; do
    if linked "$target" "$from"; then ok "$target"; else todo "$target is not linked (bash install.sh)"; fi
  done <<EOF
$(links)
EOF
  if ghostty_ok && [ -z "$(ghostty_overridden)" ]; then ok "Ghostty's settings"
  else todo "Ghostty's settings are not included, or another config overrides them (bash install.sh)"; fi
  if ! command -v jq >/dev/null 2>&1; then todo "no jq, so Claude Code's theme can't be checked"
  elif theme_ok; then ok "Claude Code's theme"
  else todo "Claude Code's theme is not set (bash install.sh)"; fi
  if rules_ok; then ok "Claude Code's shared rules"
  else todo "Claude Code's shared rules are not imported (bash install.sh)"; fi
  plugins
  changed=$(changes)
  if [ -n "$changed" ]; then
    todo "changed in this copy, discarded by the next update:"
    printf '%s\n' "$changed" | indent
  fi
}

case ${1:-install} in
  install) cmd_install ;;
  update)  cmd_update ;;
  status)  cmd_status ;;
  *) die "usage: install.sh [install | update | status]" ;;
esac
