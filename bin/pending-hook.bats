#!/usr/bin/env bats
# Tests for pending-hook.zsh. Run:  bats pending-hook.bats (beside it)
# A real interactive shell in a pseudo-terminal (script(1): util-linux's or
# BSD's) sources a copy of the hook beside a stand-in pending.sh that logs
# what it is asked to run. zsh is macOS's own, or the zsh package.
# No root, no network; the real pending.txt and history are never touched.
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell, so exports never cross tests
bats_require_minimum_version 1.5.0

setup() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/bin"
  cp "$BATS_TEST_DIRNAME/pending-hook.zsh" "$T/bin/"
  # the stand-in: logs "run LINE"; runs nothing; RC (default 0) is its exit;
  # `match` logs nothing and exits MATCH_RC (default 0: a job's command)
  cat >"$T/bin/pending.sh" <<'EOF'
#!/usr/bin/env bash
[[ $1 == match ]] && exit "${MATCH_RC:-0}"
printf '%s\n' "$*" >>"$T/asked"
exit "${RC:-0}"
EOF
  chmod +x "$T/bin/pending.sh"
  export T PENDING=$T/pending.txt HISTFILE=$T/history
  printf '%s\n' "# 1790000000 run: queued" "#  a note" "touch $T/queued" >"$PENDING"
}

# pty CMD: the shell line CMD in a pseudo-terminal, stdin typed into it;
# util-linux's script takes it with -c, BSD's (macOS) as the command after
# the file.
pty() {
  if script --version >/dev/null 2>&1; then script -qec "$1" /dev/null
  else script -q /dev/null /bin/sh -c "$1"; fi
}

# zshell LINE...: each LINE typed into an interactive zsh whose .zshrc loads
# the hook, as the Mac's clone does (before zle is loaded).
zshell() {
  mkdir -p "$T/zdot"
  printf '%s\n' "source $T/bin/pending-hook.zsh" "PS1='$ '" >"$T/zdot/.zshrc"
  printf '%s\n' "$@" exit | ZDOTDIR=$T/zdot pty "zsh -i" >/dev/null
}

@test "zsh: a job's command goes to pending run, and zsh does not run it again" {
  zshell "touch $T/queued"
  [ "$(cat "$T/asked")" = "run touch $T/queued" ]
  [ ! -e "$T/queued" ]
}

@test "zsh: \$? afterwards is the command's" {
  # shellcheck disable=SC2016  # expanded by zsh, not here
  RC=3 zshell "touch $T/queued" 'echo $? >'"$T/rc"
  [ "$(cat "$T/rc")" = 3 ]
}

@test "zsh: history keeps the line as typed, never its pending-run" {
  zshell "touch $T/queued" "touch $T/other" "fc -ln 1 >$T/hist"
  [ "$(cat "$T/asked")" = "run touch $T/queued" ]
  [ "$(head -2 "$T/hist")" = "$(printf '%s\n' "touch $T/queued" "touch $T/other")" ]
  run ! grep -q pending-run "$T/hist"
}

@test "zsh: a line pending.sh match calls no job's runs as normal, and run is never asked" {
  MATCH_RC=1 zshell "touch $T/queued"
  [ -e "$T/queued" ]
  [ ! -e "$T/asked" ]
}

@test "zsh: a job removed in between (100) runs nothing and says so" {
  RC=100 zshell "touch $T/queued" "echo done >$T/after"
  [ ! -e "$T/queued" ]
  [ -e "$T/after" ]
}

@test "zsh: a line not in pending.txt runs as normal, untouched, and pending is never asked" {
  zshell "touch $T/other" "echo '#  a note' >$T/note"
  [ -e "$T/other" ] && [ -e "$T/note" ]
  [ ! -e "$T/asked" ]
}

@test "zsh: a job's command with a redirection goes to pending too: the whole line is compared" {
  echo "touch $T/queued >/dev/null" >>"$PENDING"
  zshell "touch $T/queued >/dev/null"
  [ "$(cat "$T/asked")" = "run touch $T/queued >/dev/null" ]
}


@test "zsh: with the real pending.sh: logged, marked, ERROR on a failure, lines after still run" {
  cp "$BATS_TEST_DIRNAME/pending.sh" "$T/bin/pending.sh"
  printf '%s\n' "" "# 1790000100 no password: fails" "false" >>"$PENDING"
  export LOGS=$T/logs NOW=1790000000
  zshell "touch $T/queued" "touch $T/after"
  [ -e "$T/queued" ] && [ -e "$T/after" ]
  [ -f "$T/logs/1790000000-queued.log" ]
  grep -q '^#  ran .*: ok$' "$PENDING"
  printf '%s\n' false true exit | ZDOTDIR=$T/zdot pty "zsh -i" >"$T/out"
  grep -q 'ERROR: fails failed (exit 1)' "$T/out"
  grep -q '^#  ran .*: failed (exit 1)$' "$PENDING"
}

@test "zsh: a pending.sh without its x bit (the Mac's clone) still runs, through bash" {
  chmod -x "$T/bin/pending.sh"
  zshell "touch $T/queued"
  [ "$(cat "$T/asked")" = "run touch $T/queued" ]
}

@test "zsh: on macOS pending.txt is ~/x/pending.txt" {
  mkdir -p "$T/zdot" "$T/h/x"
  cp "$PENDING" "$T/h/x/pending.txt"
  printf '%s\n' "OSTYPE=darwin23" "source $T/bin/pending-hook.zsh" >"$T/zdot/.zshrc"
  printf '%s\n' "touch $T/queued" exit |
    HOME=$T/h PENDING='' ZDOTDIR=$T/zdot pty "zsh -i" >/dev/null
  [ "$(cat "$T/asked")" = "run touch $T/queued" ]
}

@test "zsh: a non-interactive shell sourcing it sets nothing" {
  run zsh -fc "source $T/bin/pending-hook.zsh; whence -w pending-run __pending_finish"
  [[ $output != *function* ]]
}

