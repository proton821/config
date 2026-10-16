#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # backticks and tildes are literal text in pending.txt, as the user reads it
# Tests for pending.sh, the spec. Run:  bats pending.bats (beside it)
# A pending.txt in a temp dir and a fixed NOW; no root, no network.
bats_require_minimum_version 1.5.0

setup() {
  case ${IMPL:-sh} in
    sh)   SCRIPT=$BATS_TEST_DIRNAME/pending.sh
          # A copy without its x bit (the Mac's clone) runs as an executable copy.
          if [[ ! -x $SCRIPT ]]; then
            cp "$SCRIPT" "$BATS_TEST_TMPDIR/pending.sh"
            chmod +x "$BATS_TEST_TMPDIR/pending.sh"
            SCRIPT=$BATS_TEST_TMPDIR/pending.sh
          fi ;;
    *)    echo "IMPL is sh or rust" >&2; return 1 ;;
  esac
  export PENDING=$BATS_TEST_TMPDIR/pending.txt
  export LOGS=$BATS_TEST_TMPDIR/logs
  : >"$PENDING"
}

add() { NOW=$1 "$SCRIPT" add "${@:2}"; }

# The line the by-hand jobs go below.
SEP=$(printf '%.0s-' $(seq 72))

# whats: the what of every job above the line, in file order, one per line.
whats() { sed -En '/^-+$/q; s/^# [0-9]+ [^:]+: //p' "$PENDING"; }

# prose: the by-hand paragraphs below the line, one per line, unwrapped.
prose() { awk '/^-+$/ { below = 1; next } !below { next } /^$/ { if (p != "") print p; p = ""; next } { p = p == "" ? $0 : p " " $0 } END { if (p != "") print p }' "$PENDING"; }

@test "one job: the head line, a note, the command at column 0; no blank line around it" {
  add 1790000000 "Sudo" "log in" "# where" "sudo cmd one"
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 sudo: log in\n#  where\nsudo cmd one')" ]
  [ "$(tail -c1 "$PENDING" | od -An -c | tr -d ' ')" = '\n' ]
}

@test "the head says the epoch, then the type and what after a colon" {
  add 1790000000 "Other password" "w" "c"
  add 1790000000 "Sudo + PIN" "x" "c"
  grep -qx '# 1790000000 other password: w' "$PENDING"
  grep -qx '# 1790000000 sudo + PIN: x' "$PENDING"
}


@test "order: newest first by epoch, whatever the type; by-hand jobs below the line" {
  add 1790000100 live "a job" "job.sh status x"
  add 1790000300 "Sudo" "newest" "sudo d"
  add 1790000000 run "oldest" "c"
  add 1790000200 hand "middle" "# b"
  [ "$(whats)" = "$(printf '%s\n' newest "a job" oldest)" ]
  [ "$(prose)" = "middle. b" ]
  # one blank line between jobs and either side of the line, none at either end
  [ "$(grep -c '^$' "$PENDING")" -eq 4 ]
  [ -n "$(head -1 "$PENDING")" ]
  [ -n "$(tail -1 "$PENDING")" ]
}

@test "numbered steps sharing a time keep their order" {
  add 1790000000 "Sudo" "1/2 first" "a"
  add 1790000000 "Sudo" "2/2 second" "b"
  [ "$(whats)" = "$(printf '%s\n' "1/2 first" "2/2 second")" ]
}

@test "the same job queued again keeps the time it was first queued" {
  add 1790000000 run "cheat sheet" "show.sh"
  add 1790000500 run "other" "x"
  add 1790000900 run "cheat sheet" "show.sh"
  add 1790000950 run "cheat sheet" "# a note" "show.sh"
  [ "$(grep -c 'cheat sheet' "$PENDING")" -eq 2 ]
  grep -qx '# 1790000000 run: cheat sheet' "$PENDING"
  run ! grep -q '1790000900' "$PENDING"
  # an older copy found later in the file (a hand edit, a restore) wins too
  printf '# 1790000300 boot: w\nc\n\n# 1790000100 boot: w\nc\n' >"$PENDING"
  "$SCRIPT" tidy
  [ "$(cat "$PENDING")" = "$(printf '# 1790000100 boot: w\nc')" ]
}

@test "with no NOW, a re-added job keeps its first real time" {
  "$SCRIPT" add run "w" "x"
  first=$(cat "$PENDING")
  sleep 1.1
  "$SCRIPT" add run "w" "x"
  [ "$(cat "$PENDING")" = "$first" ]
}

@test "remove: the jobs saying WHAT, or starting with it; an empty pending.txt is 0 bytes" {
  add 1790000000 boot "scan: one" "a"
  add 1790000100 boot "scan: two" "b"
  add 1790000200 boot "scan" "c"
  "$SCRIPT" remove "scan: one"
  [ "$(whats)" = "$(printf '%s\n' scan "scan: two")" ]
  "$SCRIPT" remove --prefix "scan: "
  [ "$(whats)" = scan ]
  "$SCRIPT" remove scan
  [ -f "$PENDING" ]
  [ ! -s "$PENDING" ]
}

@test "remove and tidy on a missing pending.txt create nothing" {
  rm "$PENDING"
  "$SCRIPT" remove s
  "$SCRIPT" tidy
  [ ! -e "$PENDING" ]
}

@test "has: by what, or its start" {
  add 1790000000 boot "scan found 2" "a"
  "$SCRIPT" has "scan found 2"
  "$SCRIPT" has --prefix "scan found"
  run "$SCRIPT" has "scan found"
  [ "$status" -ne 0 ]
  run "$SCRIPT" has --prefix "found"
  [ "$status" -ne 0 ]
  rm "$PENDING"
  run "$SCRIPT" has "scan found 2"
  [ "$status" -ne 0 ]
}

@test "tidy leaves a file already in order byte for byte, and orders one that isn't" {
  add 1790000000 hand "old" "# a"
  add 1790000200 boot "new" "b"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  printf '# 1790000000 boot: x\nc\n\n\n# 1790000100 run: y\nd\n' >"$PENDING"
  "$SCRIPT" tidy
  [ "$(cat "$PENDING")" = "$(printf '# 1790000100 run: y\nd\n\n# 1790000000 boot: x\nc')" ]
}


@test "a job is all comments but its command: pasted into bash, only the command runs" {
  add 1790000000 run "what" "# a note" "echo ran"
  run bash "$PENDING"
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
}

@test "the head's epoch is the plain integer; the type ends at the first colon" {
  add 1790000000 run "2 steps: 1 of them 1790000001" "c"
  [ "$(head -1 "$PENDING")" = '# 1790000000 run: 2 steps: 1 of them 1790000001' ]
  run ! grep -q '`' "$PENDING"
  run "$SCRIPT" show "2 steps: 1 of them 1790000001"
  [ "$output" = '# 1790000000 run: 2 steps: 1 of them 1790000001' ]
}


@test "a pending.txt it can't read is left alone, and the place is named" {
  printf '# 1790000000 boot: ok\nc\n\n# reboot: no stamp\n' >"$PENDING"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" add boot "w" "x"
  [ "$status" -ne 0 ]
  [[ $output == *"line 4"* ]]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  printf 'loose text\n' >"$PENDING"
  run "$SCRIPT" tidy
  [ "$status" -ne 0 ]
  [ "$(cat "$PENDING")" = "loose text" ]
}

@test "refuses bad input and changes nothing" {
  add 1790000000 boot "keep" "a"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" add boot "no line"
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh add TYPE WHAT LINE..." ]
  run "$SCRIPT" add "" "w" "x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: TYPE can't be empty" ]
  for t in "Step 2" " Reboot" "No  password" "Other: x"; do
    run "$SCRIPT" add "$t" "w" "x"
    [ "$status" -ne 0 ]; [ "$output" = "pending: a TYPE is single-spaced words, none of them only digits or with a colon" ]
  done
  run "$SCRIPT" add boot "w" ""
  [ "$status" -ne 0 ]; [ "$output" = "pending: each LINE is one non-empty line" ]
  run "$SCRIPT" add boot "w" "#x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: a LINE starting # is a note: '# text'" ]
  run "$SCRIPT" add boot "$(printf 'two\nlines')" "x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: WHAT is one line" ]
  run env NOW=soon "$SCRIPT" add boot "w" "x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: NOW is seconds since the epoch" ]
  run "$SCRIPT" remove
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh remove [--prefix] WHAT" ]
  run "$SCRIPT" has --prefix
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh has [--prefix] WHAT" ]
  run "$SCRIPT" has a b
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh has [--prefix] WHAT" ]
  run "$SCRIPT" nonsense
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh add|remove|has|tidy|show|match|ran|run (see the top of this file)" ]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
}

@test "the file is 72 wide: add refuses a longer head line or note; a command is as long as it is" {
  w59=$(printf '%.0s=' $(seq 59))
  add 1790000000 "manual" "${w59:8}" "$(printf '%.0s=' $(seq 72))" "# $(printf '%.0s=' $(seq 69))"
  [ "$(awk 'length > 72' "$PENDING")" = "" ]
  [ "$(awk 'length == 72' "$PENDING" | wc -l)" -eq 3 ]
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" add "manual" "${w59:7}" "c"
  [ "$status" -ne 0 ]; [ "$output" = "pending: the head line is 73 characters, over 72: shorten WHAT" ]
  run "$SCRIPT" add "manual" "w" "# $(printf '%.0s=' $(seq 70))"
  [ "$status" -ne 0 ]; [[ $output == "pending: a note is 73 characters as written, over 72: "* ]]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  long="some-command --with $(printf '%.0s--option=value ' $(seq 12))--last"
  add 1790000100 "run" "a long command" "$long"
  grep -qxF "$long" "$PENDING"
  run "$SCRIPT" match "$long"
  [ "$status" -eq 0 ]
  "$SCRIPT" remove "a long command"
  # characters, not bytes, whatever the locale
  LC_ALL=C add 1790000000 "manual" "${w59:9}é" "c"
  cmp -s "$PENDING" "$BATS_TEST_TMPDIR/before" && false
  # a line already wider is read and kept as it is
  printf '# 1790000000 manual: %s\nc\n' "$(printf '%.0s=' $(seq 80))" >"$PENDING"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
}

@test "add with no NOW stamps the current time" {
  before=$(date +%s)
  "$SCRIPT" add run "w" "x"
  after=$(date +%s)
  t=$(sed -En '1s/^# ([0-9]+) run: w$/\1/p' "$PENDING")
  (( t >= before && t <= after ))
}

@test "show: the head lines only, newest first, then the by-hand prose; or only the jobs saying a WHAT" {
  add 1790000000 run "old" "# a note" "cmd a"
  add 1790000200 "Sudo" "new" "sudo b"
  add 1790000100 hand "middle" "# step"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" show
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' '# 1790000200 sudo: new' '# 1790000000 run: old' "$SEP" '' 'middle. step')" ]
  run "$SCRIPT" show old new nothing
  [ "$output" = "$(printf '%s\n' '# 1790000200 sudo: new' '# 1790000000 run: old')" ]
  run "$SCRIPT" show middle
  [ "$output" = "$(printf '%s\n' "$SEP" '' 'middle. step')" ]
  run "$SCRIPT" show nothing
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
}

@test "show WHAT succeeds when pending.txt's last job is another one" {
  add 1790000200 "Sudo" "wanted" "sudo b"
  add 1790000100 hand "last in the file" "# step"
  run "$SCRIPT" show wanted
  [ "$status" -eq 0 ]
  [ "$output" = "# 1790000200 sudo: wanted" ]
}

@test "show on a missing or empty pending.txt prints nothing and creates nothing" {
  run "$SCRIPT" show
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$PENDING"
  run "$SCRIPT" show
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$PENDING" ]
}

@test "show reads an out-of-order file in pending.txt's order, and leaves it as it is" {
  printf '# 1790000000 boot: x\nc\n\n# 1790000100 sudo: y\nd\n' >"$PENDING"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" show
  [ "${lines[0]}" = '# 1790000100 sudo: y' ]
  [ "${lines[1]}" = '# 1790000000 boot: x' ]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
}

@test "show takes only head lines, never a note or command that looks like one" {
  printf '# 1790000100 sudo: y\n# 1790000999 run: looks like a head\n' >"$PENDING"
  run "$SCRIPT" show
  [ "$output" = '# 1790000100 sudo: y' ]
}

@test "by-hand jobs are one paragraph below the line: run on, wrapped at 72, no prefix" {
  add 1790000000 run "free" "c"
  add 1790000100 hand "open the app and turn the setting on" "# 1. Settings > Privacy:" \
    "# pick the second option, then Save" "# afterwards tell Claude" "~/x/done.sh item"
  text='open the app and turn the setting on. 1. Settings > Privacy: pick the second option, then Save. afterwards tell Claude. ~/x/done.sh item'
  [ "$(cat "$PENDING")" = "$(printf '%s\n' '# 1790000000 run: free' 'c' '' "$SEP" '' \
    'open the app and turn the setting on. 1. Settings > Privacy: pick the' \
    'second option, then Save. afterwards tell Claude. ~/x/done.sh item')" ]
  [ "${#SEP}" -eq 72 ]
  [ "$(awk 'length > 72' "$PENDING")" = "" ]
  [ "$(prose)" = "$text" ]
  run ! grep -qi 'by hand' "$PENDING"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  # known by its what, which the prose runs on from
  "$SCRIPT" has "open the app and turn the setting on"
  run "$SCRIPT" has "open the app"
  [ "$status" -ne 0 ]
  "$SCRIPT" has --prefix "open the app"
  "$SCRIPT" remove "free"
  [ "$(cat "$PENDING")" = "$(printf '%s\n' "$SEP" '' \
    'open the app and turn the setting on. 1. Settings > Privacy: pick the' \
    'second option, then Save. afterwards tell Claude. ~/x/done.sh item')" ]
  "$SCRIPT" remove "open the app and turn the setting on"
  [ ! -s "$PENDING" ]
}

@test "by-hand prose: a word longer than 72 stands alone; blanks are single spaces" {
  long=https://example.org/$(printf '%.0s0' $(seq 70))
  add 1790000000 hand "go  to" "# $long" "# and   back."
  [ "$(cat "$PENDING")" = "$(printf '%s\n' "$SEP" '' 'go to.' "$long." 'and back.')" ]
  "$SCRIPT" has "go  to"
}

@test "below the line a new job goes on top, and the same job again stays where it is" {
  add 1790000000 hand "first" "# a"
  add 1790000100 hand "second" "# b"
  add 1790000200 hand "first" "# a"
  [ "$(prose)" = "$(printf '%s\n' 'second. b' 'first. a')" ]
  add 1790000300 hand "third" "c"
  [ "$(prose)" = "$(printf '%s\n' 'third. c' 'second. b' 'first. a')" ]
}

# ------------------------------------------------------- match, ran, run
@test "match: the job whose command is LINE, newest first; never a note or a by-hand job" {
  add 1790000000 sudo "older" "# cmd two" "cmd two"
  add 1790000100 sudo "newer" "cmd two"
  add 1790000200 hand "click it" "# cmd three"
  run "$SCRIPT" match "cmd two"
  [ "$status" -eq 0 ]; [ "$output" = "$(printf '1790000100\tnewer')" ]
  run "$SCRIPT" match "cmd three"; [ "$status" -eq 1 ]; [ -z "$output" ]
  run "$SCRIPT" match "cmd"; [ "$status" -eq 1 ]
}


@test "ran: a first note with the time and the result; a second run replaces it" {
  add 1790000000 sudo "do it" "# a note" "cmd one"
  TZ=UTC NOW=1790000000 run "$SCRIPT" ran "do it" 0
  [ "$status" -eq 0 ]
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 sudo: do it\n#  ran Mon 21 Sep, 2:13pm: ok\n#  a note\ncmd one')" ]
  TZ=UTC NOW=1790003600 "$SCRIPT" ran "do it" 2
  [ "$(sed -n 2,3p "$PENDING")" = "$(printf '#  ran Mon 21 Sep, 3:13pm: failed (exit 2)\n#  a note')" ]
  [ "$(grep -c '^#  ran ' "$PENDING")" = 1 ]
  "$SCRIPT" has "do it"
}

@test "ran refuses a job that isn't there, and a bad exit" {
  add 1790000000 sudo "do it" "cmd one"
  run "$SCRIPT" ran "not it" 0; [ "$status" -ne 0 ]; [[ $output == *"no job says: not it"* ]]
  run "$SCRIPT" ran "do it" x; [ "$status" -ne 0 ]
}

@test "run: the command runs, its output kept in the job's log, the job marked; its exit passed on" {
  add 1790000000 run "Say hello!" "echo hello; exit 3"
  TZ=UTC NOW=1790000000 run "$SCRIPT" run "echo hello; exit 3"
  [ "$status" -eq 3 ]
  [[ $output == *hello* ]]
  log=$LOGS/1790000000-say-hello.log
  [ "$(head -1 "$log")" = "# Say hello!" ]
  grep -q hello "$log"
  [ "$(stat -c %a "$LOGS" 2>/dev/null || stat -f %Lp "$LOGS")" = 700 ]
  [ "$(sed -n 2p "$PENDING")" = "#  ran Mon 21 Sep, 2:13pm: failed (exit 3)" ]
}

@test "run: a failure ends with ERROR on the terminal, not in the log; a success has none" {
  add 1790000000 run "Fail" "echo out; exit 3"
  add 1790000100 run "Pass" "echo fine"
  run --separate-stderr "$SCRIPT" run "echo out; exit 3"
  [ "$status" -eq 3 ]
  [ "$stderr" = "ERROR: Fail failed (exit 3)" ]
  run ! grep -q ERROR "$LOGS/1790000000-fail.log"
  run --separate-stderr "$SCRIPT" run "echo fine"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "pending.txt is ~/pending.txt on the rig, ~/x/pending.txt on the Mac" {
  local home=$BATS_TEST_TMPDIR/home
  mkdir -p "$home/x" "$BATS_TEST_TMPDIR/mac"
  printf '#!/bin/sh\necho Darwin\n' >"$BATS_TEST_TMPDIR/mac/uname"
  chmod +x "$BATS_TEST_TMPDIR/mac/uname"
  HOME=$home PENDING='' "$SCRIPT" add run "Here" "true"
  grep -q "run: Here" "$home/pending.txt"
  HOME=$home PENDING='' PATH=$BATS_TEST_TMPDIR/mac:$PATH "$SCRIPT" add run "There" "true"
  grep -q "run: There" "$home/x/pending.txt"
  run ! grep -q There "$home/pending.txt"
}


# A message: what a Slack message, a Jira or PR comment looks like.
long=$(printf '%.0s word' $(seq 40))

@test "message: its lines as given, of any length, blank and # lines too, and the next job read after it" {
  add 1790000000 run "first" "cmd one"
  add 1790000100 message "Slack #team: the release" "# Release notes" "" "Hi all,$long" "" "---" "  - indented" "#  not a note"
  add 1790000200 sudo "last" "cmd two"
  [ "$(cat "$PENDING")" = "$(printf '%s\n' "# 1790000200 sudo: last" "cmd two" "" \
    "# 1790000100 message: Slack #team: the release" "# Release notes" "" "Hi all,$long" "" "---" "  - indented" "#  not a note" "" \
    "# 1790000000 run: first" "cmd one")" ]
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  [ "$("$SCRIPT" show)" = "$(printf '%s\n' "# 1790000200 sudo: last" "# 1790000100 message: Slack #team: the release" "# 1790000000 run: first")" ]
}

@test "message: from stdin with no LINEs, blank lines at its ends dropped" {
  printf '\n\nline one\n\nline two\n\n' | NOW=1790000000 "$SCRIPT" add message "Jira ABC-1: a comment"
  [ "$(cat "$PENDING")" = "$(printf '%s\n' "# 1790000000 message: Jira ABC-1: a comment" "line one" "" "line two")" ]
}

@test "message: never a command, never marked; show gives its head line only" {
  add 1790000000 message "PR 12: a comment" "touch $BATS_TEST_TMPDIR/made"
  run "$SCRIPT" match "touch $BATS_TEST_TMPDIR/made"
  [ "$status" -eq 1 ]
  run "$SCRIPT" run "touch $BATS_TEST_TMPDIR/made"
  [ "$status" -eq 100 ]; [ ! -e "$BATS_TEST_TMPDIR/made" ]
  run "$SCRIPT" ran "PR 12: a comment" 0
  [ "$status" -ne 0 ]
  [ "$("$SCRIPT" show)" = "# 1790000000 message: PR 12: a comment" ]
}

@test "message: refused empty, or holding a line pending.txt would read as a head or the line" {
  run "$SCRIPT" add message "m" "" "  "
  [ "$status" -ne 0 ]; [ "$output" = "pending: a message can't be empty" ]
  run "$SCRIPT" add message "m" "text" "$SEP"
  [ "$status" -ne 0 ]; [[ $output == "pending: a message's line would end it in pending.txt: "* ]]
  run "$SCRIPT" add message "m" "# 1790000000 run: x"
  [ "$status" -ne 0 ]
  [ ! -s "$PENDING" ]
  # its head line is still 72 wide at most
  run "$SCRIPT" add message "$(printf '%.0s=' $(seq 60))" "text"
  [ "$status" -ne 0 ]; [[ $output == "pending: the head line is "*", over 72: shorten WHAT" ]]
}

@test "run: a line that is no job's runs nothing and exits 100" {
  add 1790000000 sudo "do it" "cmd one"
  run "$SCRIPT" run "touch $BATS_TEST_TMPDIR/made"
  [ "$status" -eq 100 ]
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
  [ ! -e "$LOGS" ]
}

@test "remove deletes the job's log with it, and no other" {
  add 1790000000 sudo "one" "true"
  add 1790000100 sudo "two" "true"
  "$SCRIPT" run true
  ls "$LOGS"/1790000100-two.log
  : >"$LOGS/1790000000-one.log"
  "$SCRIPT" remove two
  [ ! -e "$LOGS/1790000100-two.log" ]
  [ -e "$LOGS/1790000000-one.log" ]
}

@test "the test data is generic: no real service, account or address" {
  run grep -niE 'proton|google|gcp|youtube|github|gitlab|nord|bitwarden|authy|whatsapp|chromium|herdr|LINE[0-9]|@[a-z0-9-]+\.(com|me|net|co)\b' "$BATS_TEST_FILENAME"
  # this test's own pattern is the one match allowed
  [ "${#lines[@]}" -eq 1 ]
}
