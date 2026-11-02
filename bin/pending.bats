#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # backticks and tildes are literal text in pending.txt, as the user reads it
# shellcheck disable=SC2312  # the test idiom: a $(...) inside a [ ... ] that compares what it printed
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

# pty CMD: the shell line CMD in a pseudo-terminal, stdin typed into it;
# util-linux's script takes it with -c, BSD's (macOS) as the command after
# the file.
pty() {
  if script --version >/dev/null 2>&1; then script -qec "$1" /dev/null
  else script -q /dev/null /bin/sh -c "$1"; fi
}

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

@test "a chain's steps sharing a time keep their order" {
  add 1790000000 "Sudo" "pack 1/2 first" "a"
  add 1790000000 "Sudo" "pack 2/2 second" "b"
  [ "$(whats)" = "$(printf '%s\n' "pack 1/2 first" "pack 2/2 second")" ]
}

@test "the most recently added job is on top, even in the same second" {
  add 1790000000 run "first" "a"
  add 1790000000 run "second" "b"
  add 1790000000 run "third" "c"
  [ "$(whats)" = "$(printf '%s\n' third second first)" ]
  add 1790000000 run "pack 1/2 x" "d"
  add 1790000000 run "pack 2/2 y" "e"
  add 1790000000 run "fourth" "f"
  [ "$(whats)" = "$(printf '%s\n' fourth "pack 1/2 x" "pack 2/2 y" third second first)" ]
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
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

@test "remove: a log it can't delete doesn't stop the job going" {
  add 1790000000 run "stuck" "cmd"
  mkdir -p "$LOGS"; : >"$LOGS/1790000000-stuck.log"; chmod 500 "$LOGS"
  run "$SCRIPT" remove "stuck"
  chmod 700 "$LOGS"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -s "$PENDING" ]
  [ -f "$LOGS/1790000000-stuck.log" ]
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

@test "ggdG: an emptied pending.txt, with or without its newline, is 0 bytes and takes the next job" {
  add 1790000000 run "gone" "a"
  : >"$PENDING"
  "$SCRIPT" tidy
  [ ! -s "$PENDING" ]
  printf '\n' >"$PENDING"
  run "$SCRIPT" show
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run "$SCRIPT" has gone
  [ "$status" -eq 1 ]
  "$SCRIPT" tidy
  [ ! -s "$PENDING" ]
  add 1790000100 run "next" "b"
  [ "$(cat "$PENDING")" = "$(printf '# 1790000100 run: next\nb')" ]
  rm "$PENDING"
  add 1790000100 run "again" "b"
  [ "$(whats)" = again ]
  : >"$PENDING"
  run "$SCRIPT" remove nothing
  [ "$status" -eq 0 ]
}

@test "d4<CR>: lines with no head are ignored, and the next change moves them out, whole, saying so" {
  printf '#  a note\ncmd loose\n\n# 1790000100 run: real\ncmd real\n' >"$PENDING"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" has real
  run "$SCRIPT" has "cmd loose"; [ "$status" -eq 1 ]
  run "$SCRIPT" show; [ "$output" = "# 1790000100 run: real" ]
  run "$SCRIPT" match "cmd real"; [ "$status" -eq 0 ]
  run "$SCRIPT" match "cmd loose"; [ "$status" -eq 1 ]
  run "$SCRIPT" run "cmd loose"; [ "$status" -eq 100 ]
  # reading changed nothing
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run --separate-stderr env NOW=1790000200 "$SCRIPT" add run "new" "cmd new"
  [ "$status" -eq 0 ]
  [ "$stderr" = "pending: moved 2 line(s) with no job to $LOGS/orphans.txt" ]
  [ "$(cat "$PENDING")" = "$(printf '# 1790000200 run: new\ncmd new\n\n# 1790000100 run: real\ncmd real')" ]
  grep -qxF "#  a note" "$LOGS/orphans.txt"
  grep -qxF "cmd loose" "$LOGS/orphans.txt"
  [ "$(stat -c %a "$LOGS" 2>/dev/null || stat -f %Lp "$LOGS")" = 700 ]
  # anything typed above the line goes the same way, with nothing lost
  printf 'loose text\n' >"$PENDING"
  "$SCRIPT" tidy 2>/dev/null
  [ ! -s "$PENDING" ]
  grep -qxF "loose text" "$LOGS/orphans.txt"
}

@test "d4<CR>: a head line with nothing of its job left goes out too; a hand or note-only job stays" {
  printf '# 1790000300 run: only a head\n\n# 1790000200 run: head and mark\n#  ran Mon 21 Sep, 2:13pm: ok\n\n# 1790000100 boot: a note\n#  it stays\n\n# 1790000000 hand: a paragraph\n' >"$PENDING"
  run "$SCRIPT" has "only a head"; [ "$status" -eq 1 ]
  "$SCRIPT" tidy 2>/dev/null
  [ "$(whats)" = "a note" ]
  [ "$(prose)" = "a paragraph" ]
  grep -qxF "# 1790000300 run: only a head" "$LOGS/orphans.txt"
  grep -qxF "#  ran Mon 21 Sep, 2:13pm: ok" "$LOGS/orphans.txt"
}

@test "a head line starts a job wherever it stands: no blank line before it, or below the line" {
  printf '# 1790000200 run: one\ncmd a\n# 1790000100 sudo: two\ncmd b\n' >"$PENDING"
  "$SCRIPT" has two
  run "$SCRIPT" show
  [ "$output" = "$(printf '# 1790000200 run: one\n# 1790000100 sudo: two')" ]
  "$SCRIPT" tidy
  [ "$(cat "$PENDING")" = "$(printf '# 1790000200 run: one\ncmd a\n\n# 1790000100 sudo: two\ncmd b')" ]
  printf '%s\n' "$SEP" '' 'by hand it is' '' '# 1790000100 sudo: two' 'cmd b' '' 'and more' >"$PENDING"
  "$SCRIPT" tidy
  [ "$(whats)" = "two" ]
  [ "$(prose)" = "$(printf 'by hand it is\nand more')" ]
  # a line cut down to a few hyphens is still the line; lower down, it is prose
  printf '%s\n' '---' '' 'by hand it is' '---' >"$PENDING"
  "$SCRIPT" tidy
  [ "$(prose)" = "by hand it is ---" ]
}

@test "stray characters in the line, outside a job: it is still the line, and the by-hand jobs stay" {
  add 1790000000 run "w" "c"
  add 1790000100 hand "a step" "# in the app"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  sed -i.bak -E 's/^-{5}/--x--y-/' "$PENDING"
  "$SCRIPT" has "a step"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  [ ! -e "$LOGS/orphans.txt" ]
  # inside a job, a command full of hyphens is a command
  long=$(printf '%.0s-' $(seq 40))
  add 1790000200 run "hyphens" "echo $long"
  "$SCRIPT" tidy
  run "$SCRIPT" match "echo $long"
  [ "$status" -eq 0 ]
  "$SCRIPT" has "a step"
}

@test "an epoch too long to count isn't a head" {
  printf '# 1234567890123456789 run: w\nc\n' >"$PENDING"
  run "$SCRIPT" show
  [ -z "$output" ]
}

@test "a blank line cut in a message's head costs nothing; tidy never grows it" {
  printf '# 1790000000 message: m\n\n\ntext\n' >"$PENDING"
  "$SCRIPT" tidy
  "$SCRIPT" tidy
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 message: m\ntext')" ]
}

@test "refuses bad input and changes nothing" {
  add 1790000000 boot "keep" "a"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" add boot "no line"
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh add TYPE WHAT LINE..." ]
  run "$SCRIPT" add "" "w" "x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: TYPE can't be empty" ]
  run "$SCRIPT" add boot "   " "x"
  [ "$status" -ne 0 ]; [ "$output" = "pending: WHAT can't be empty" ]
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
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh add|remove|has|tidy|show|result|status|version|match|ran|run|ended (see the top of this file)" ]
  run "$SCRIPT" result
  [ "$status" -ne 0 ]; [ "$output" = "pending: usage: pending.sh result WHAT" ]
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

@test "a WHAT's blanks are single spaces, and blanks around a command go" {
  add 1790000000 run "  two   words " "   cmd   a  " "# a  note"
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 run: two words\ncmd   a\n#  a  note')" ]
  "$SCRIPT" has "two  words"
  run "$SCRIPT" match "cmd   a"; [ "$status" -eq 0 ]
  "$SCRIPT" remove "two   words "
  [ ! -s "$PENDING" ]
}

@test "a WHAT is only text, in a chain's name too" {
  cd "$BATS_TEST_TMPDIR"
  add 1790000000 run "\$(touch made) 1/2 x" "cmd a"
  add 1790000000 run "\$(touch made) 2/2 y" "cmd b"
  "$SCRIPT" tidy
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
  [ "$(grep -c '^# ' "$PENDING")" -eq 2 ]
}

@test "order: numbered steps stay together in step order, however they were queued" {
  : >"$PENDING"
  add 1790000100 "Run" "older job" "a"
  add 1790000300 "Run" "pack, 2/3 middle" "c"
  add 1790000200 "Run" "pack, 1/3 first" "b"
  add 1790000400 "Run" "pack, 3/3 last" "d"
  add 1790000350 "Run" "other 2/2" "f"
  add 1790000350 "Run" "other 1/2" "e"
  add 1790000500 "Run" "newest job" "g"
  [ "$(whats)" = "$(printf '%s\n' "newest job" "pack, 1/3 first" "pack, 2/3 middle" "pack, 3/3 last" "other 1/2" "other 2/2" "older job")" ]
}

@test "a chain's first step needs its name: nameless chains can't be told apart" {
  for w in "1/2 read it" "(1/2) read it" "[1/2] read it" "  1/2 read it"; do
    run "$SCRIPT" add run "$w" "c"
    [ "$status" -ne 0 ]; [[ $output == "pending: a chain's WHAT starts with its NAME, the same in every step ("* ]]
  done
  [ ! -s "$PENDING" ]
  # no step, so nothing to refuse
  add 1790000000 run "24/7 feed" "a"
  add 1790000000 run "1/1 all" "b"
  add 1790000000 run "1/2/3 path" "c"
  add 1790000000 run "12/2024 report" "d"
  [ "$(grep -c '^# ' "$PENDING")" -eq 4 ]
}

@test "chains: two in the file with no name stay apart, each whole, by when they were queued" {
  printf '%s\n' '# 1790000300 run: 2/2 beta do' 'b2' '' '# 1790000200 run: 1/2 beta read' 'b1' '' \
    '# 1790000100 run: 2/2 alpha do' 'a2' '' '# 1790000000 run: 1/2 alpha read' 'a1' >"$PENDING"
  "$SCRIPT" tidy
  [ "$(whats)" = "$(printf '%s\n' '1/2 beta read' '2/2 beta do' '1/2 alpha read' '2/2 alpha do')" ]
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run "$SCRIPT" show
  [ "${lines[0]}" = '# 1790000200 run: 1/2 beta read' ]
  [ "${lines[3]}" = '# 1790000100 run: 2/2 alpha do' ]
}

@test "chains: named ones never mix, and the same name again is a second chain" {
  add 1790000000 run "pack 1/2 old" "a"
  add 1790000100 run "other 1/2 x" "b"
  add 1790000200 run "pack 2/2 old" "c"
  add 1790000300 run "other 2/2 y" "d"
  add 1790000400 run "alone" "e"
  [ "$(whats)" = "$(printf '%s\n' alone "other 1/2 x" "other 2/2 y" "pack 1/2 old" "pack 2/2 old")" ]
  add 1790000500 run "pack 1/2 new" "f"
  add 1790000501 run "pack 2/2 new" "g"
  [ "$(whats)" = "$(printf '%s\n' "pack 1/2 new" "pack 2/2 new" alone "other 1/2 x" "other 2/2 y" "pack 1/2 old" "pack 2/2 old")" ]
  # the most recently added chain is on top even when an old one gets a step
  add 1790000600 run "other 1/3 z" "h"
  add 1790000601 run "lone" "i"
  add 1790000602 run "other 3/3 z" "j"
  [ "$(whats | head -3)" = "$(printf '%s\n' "other 1/3 z" "other 3/3 z" lone)" ]
}

@test "chains: the first N/M in a WHAT is the step; another pair or a number later is no matter" {
  add 1790000000 run "pack 1/3 from 24/7 feed" "a"
  add 1790000100 run "pack 2/3 of 5/9 parts" "b"
  add 1790000300 run "other" "c"
  add 1790000200 run "pack 3/3: end" "d"
  [ "$(whats)" = "$(printf '%s\n' other "pack 1/3 from 24/7 feed" "pack 2/3 of 5/9 parts" "pack 3/3: end")" ]
  # 9/3 isn't a step, so the pair after it is
  add 1790000400 run "a 9/3 b 1/2" "e"
  add 1790000401 run "z" "f"
  add 1790000402 run "a 9/3 b 2/2" "g"
  [ "$(whats | head -3)" = "$(printf '%s\n' "a 9/3 b 1/2" "a 9/3 b 2/2" z)" ]
}

@test "chains: below the line too, a by-hand chain stays in step order" {
  add 1790000000 hand "open it 1/2: the first" "# a"
  add 1790000100 hand "other job" "# x"
  add 1790000200 hand "open it 2/2: the second" "# b"
  [ "$(prose)" = "$(printf '%s\n' 'open it 1/2: the first. a' 'open it 2/2: the second. b' 'other job. x')" ]
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

@test "ran: only its own mark is replaced; a note of the user's saying ran stays" {
  add 1790000000 sudo "do it" "# ran out of space last time" "# ran Mon 21 Sep, 2:13pm: ok" "cmd one"
  TZ=UTC NOW=1790000000 "$SCRIPT" ran "do it" 0
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 sudo: do it\n#  ran Mon 21 Sep, 2:13pm: ok\n#  ran out of space last time\n#  ran Mon 21 Sep, 2:13pm: ok\ncmd one')" ]
  TZ=UTC NOW=1790000000 "$SCRIPT" ran "do it" 4
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 sudo: do it\n#  ran Mon 21 Sep, 2:13pm: failed (exit 4)\n#  ran out of space last time\n#  ran Mon 21 Sep, 2:13pm: ok\ncmd one')" ]
}

@test "the same job queued again after it ran is one job, waiting again, its mark gone" {
  add 1790000000 run "do it" "true"
  TZ=UTC NOW=1790000100 "$SCRIPT" run true
  grep -q '^#  ran ' "$PENDING"
  add 1790000200 run "do it" "true"
  [ "$(cat "$PENDING")" = "$(printf '# 1790000000 run: do it\ntrue')" ]
}

@test "ran refuses a job that isn't there, and a bad exit" {
  add 1790000000 sudo "do it" "cmd one"
  run "$SCRIPT" ran "not it" 0; [ "$status" -ne 0 ]; [[ $output == *"no job says: not it"* ]]
  run "$SCRIPT" ran "do it" x; [ "$status" -ne 0 ]
}

@test "run: the command runs, its output kept in the job's log, the job marked; its exit passed on" {
  add 1790000000 run "Say hello!" "bash -c 'echo hello; exit 3'"
  TZ=UTC NOW=1790000000 run "$SCRIPT" run "bash -c 'echo hello; exit 3'"
  [ "$status" -eq 3 ]
  [[ $output == *hello* ]]
  log=$LOGS/1790000000-say-hello.log
  [ "$(head -1 "$log")" = "# Say hello!" ]
  grep -q hello "$log"
  [ "$(stat -c %a "$LOGS" 2>/dev/null || stat -f %Lp "$LOGS")" = 700 ]
  [ "$(sed -n 2p "$PENDING")" = "#  ran Mon 21 Sep, 2:13pm: failed (exit 3)" ]
}

@test "run: a failure ends with ERROR on the terminal, not in the log; a success has none" {
  add 1790000000 run "Fail" "bash -c 'echo out; exit 3'"
  add 1790000100 run "Pass" "echo fine"
  run --separate-stderr "$SCRIPT" run "bash -c 'echo out; exit 3'"
  [ "$status" -eq 3 ]
  [ "$stderr" = "ERROR: Fail failed (exit 3)" ]
  run ! grep -q ERROR "$LOGS/1790000000-fail.log"
  run --separate-stderr "$SCRIPT" run "echo fine"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "run: a job gone from the file while its command ran ends as the command did" {
  export GONE=$PENDING
  add 1790000000 run "cut by hand" 'bash -c ": >\"\$GONE\"; exit 3"'
  run "$SCRIPT" run 'bash -c ": >\"\$GONE\"; exit 3"'
  [ "$status" -eq 3 ]
  [[ $output == *"ERROR: cut by hand failed (exit 3)"* ]]
  [ ! -s "$PENDING" ]
  add 1790000000 run "cut by hand" 'bash -c "rm \"\$GONE\""'
  run "$SCRIPT" run 'bash -c "rm \"\$GONE\""'
  [ "$status" -eq 0 ]
  [ ! -e "$PENDING" ]
}

@test "run: a command exiting 100 comes back as 1, so the hook can't run it again; the mark has its 100" {
  add 1790000000 run "hundred" 'bash -c "exit 100"'
  TZ=UTC NOW=1790000000 run "$SCRIPT" run 'bash -c "exit 100"'
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR: hundred failed (exit 100)"* ]]
  [ "$(sed -n 2p "$PENDING")" = "#  ran Mon 21 Sep, 2:13pm: failed (exit 100)" ]
}

@test "run: no log can be kept, so nothing ran here (100): the shell runs it as usual" {
  add 1790000000 run "unlogged" "touch $BATS_TEST_TMPDIR/made"
  : >"$BATS_TEST_TMPDIR/file"
  LOGS=$BATS_TEST_TMPDIR/file/logs run "$SCRIPT" run "touch $BATS_TEST_TMPDIR/made"
  [ "$status" -eq 100 ]
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
  run grep -c '^#  ran' "$PENDING"; [ "$output" = 0 ]
}

@test "run: the command sees the caller's locale, not this script's" {
  add 1790000000 run "locale" "printenv LC_ALL"
  LC_ALL=POSIX run "$SCRIPT" run "printenv LC_ALL"
  [ "$status" -eq 0 ]; [ "$output" = POSIX ]
  run env -u LC_ALL "$SCRIPT" run "printenv LC_ALL"
  [ "$status" -eq 1 ]
  [[ $output != *UTF-8* ]]
}

@test "run: only the job that runs the line is marked, not another with the same what" {
  add 1790000000 run "twice" "cmd one"
  add 1790000100 run "twice" "true"
  TZ=UTC NOW=1790000200 "$SCRIPT" run true
  [ "$(cat "$PENDING")" = "$(printf '# 1790000100 run: twice\n#  ran Mon 21 Sep, 2:16pm: ok\ntrue\n\n# 1790000000 run: twice\ncmd one')" ]
}

@test "run: Ctrl-C reaches the command, the job is still marked, and what it prints after is logged" {
  command -v script >/dev/null || skip "no script"
  printf '%s\n' "trap 'echo after the signal; exit 7' INT" 'sleep 30 &' 'wait' >"$BATS_TEST_TMPDIR/c.sh"
  add 1790000000 run "stop me" "bash $BATS_TEST_TMPDIR/c.sh"
  add 1790000100 run "stop too" "sleep 31"
  # the pseudo-terminal turns the byte into SIGINT for the command's group
  { sleep 1; printf '\003'; sleep 1; } | pty "'$SCRIPT' run 'bash $BATS_TEST_TMPDIR/c.sh'" >/dev/null || true
  grep -q 'after the signal' "$LOGS/1790000000-stop-me.log"
  grep -q '^#  ran .*: failed (exit 7)$' "$PENDING"
  { sleep 1; printf '\003'; sleep 1; } | pty "'$SCRIPT' run 'sleep 31'" >/dev/null || true
  grep -q '^#  ran .*: failed (exit 130)$' "$PENDING"
  [ ! -d "$PENDING.lock" ]
}

@test "run: a process the command leaves behind holding its output doesn't hold the prompt" {
  add 1790000000 run "daemon" "bash -c 'sleep 6 & echo started'"
  local start=$SECONDS
  "$SCRIPT" run "bash -c 'sleep 6 & echo started'" >"$BATS_TEST_TMPDIR/out" 3>&-
  (( SECONDS - start < 5 ))
  grep -q started "$BATS_TEST_TMPDIR/out"
  grep -q '^#  ran .*: ok$' "$PENDING"
  grep -q '^#  ran .*: ok$' "$LOGS/1790000000-daemon.log"
}

# ------------------------------------------------------- what stays, what goes
# A log's time is the file's, so these go by the real clock.

# aged LOG: LOG's time, long ago.
aged() { touch -t 202001010000 "$1"; }

@test "a job stays until it is removed or cut: failed, never run, or a step of a chain still open, however old" {
  add 1790000001 run "broke" "false"
  add 1790000002 run "not yet" "echo nope"
  add 1790000003 run "pack 2/2 last" "printf x"
  add 1790000003 run "pack 1/2 first" "echo first"
  run "$SCRIPT" run false
  "$SCRIPT" run "printf x"
  aged "$LOGS/1790000001-broke.log"; aged "$LOGS/1790000003-pack-2-2-last.log"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  NOW=2000000000 "$SCRIPT" tidy
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
}

@test "a job that ran ok goes after a day, its log left for result; a whole chain goes together" {
  local now
  now=$(date +%s)
  add "$now" run "did it" "true"
  add "$now" run "pack 1/2 first" "echo first"
  add "$now" run "pack 2/2 last" "printf x"
  "$SCRIPT" run true
  "$SCRIPT" run "echo first" >/dev/null
  "$SCRIPT" run "printf x" >/dev/null
  NOW=$((now + 86400 - 60)) "$SCRIPT" tidy
  "$SCRIPT" has "did it"
  NOW=$((now + 86400 + 60)) "$SCRIPT" tidy
  [ ! -s "$PENDING" ]
  run "$SCRIPT" result "did it"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "gone from pending.txt, ran "*": ok" ]]
}

@test "a job marked ok with no log stays: nothing says when it ran" {
  add 1790000000 run "marked" "c"
  "$SCRIPT" ran "marked" 0
  NOW=2000000000 "$SCRIPT" tidy
  "$SCRIPT" has "marked"
}


@test "a log with no job and orphans.txt go after 14 days untouched; a waiting job's log stays" {
  add 1790000000 run "keep" "echo keep"
  mkdir -p "$LOGS"
  : >"$LOGS/1000-old.log"; : >"$LOGS/1001-new.log"; : >"$LOGS/orphans.txt"; : >"$LOGS/other.txt"; : >"$LOGS/1790000000-keep.log"
  aged "$LOGS/1000-old.log"; aged "$LOGS/orphans.txt"; aged "$LOGS/other.txt"; aged "$LOGS/1790000000-keep.log"
  "$SCRIPT" tidy
  [ ! -e "$LOGS/1000-old.log" ] && [ ! -e "$LOGS/orphans.txt" ]
  [ -e "$LOGS/1001-new.log" ] && [ -e "$LOGS/other.txt" ] && [ -e "$LOGS/1790000000-keep.log" ]
}

# ------------------------------------------------------- result, status, version
@test "result: waiting, or its mark; its log; exit 1 when nothing is known" {
  add 1790000000 run "a job" "true"
  add 1790000100 hand "a step" "# in the app"
  run "$SCRIPT" result "a job"
  [ "$status" -eq 0 ]; [ "$output" = waiting ]
  run "$SCRIPT" result "a step"
  [ "$status" -eq 0 ]; [ "$output" = waiting ]
  TZ=UTC NOW=1790000000 "$SCRIPT" run true
  run "$SCRIPT" result "a job"
  [ "${lines[0]}" = "ran Mon 21 Sep, 2:13pm: ok" ]
  [ "${lines[1]}" = "log: $LOGS/1790000000-a-job.log" ]
  [ "$(tail -1 "$LOGS/1790000000-a-job.log")" = "#  ran Mon 21 Sep, 2:13pm: ok" ]
  : >"$PENDING"
  run "$SCRIPT" result "a job"
  [ "${lines[0]}" = "gone from pending.txt, ran Mon 21 Sep, 2:13pm: ok" ]
  # a log that only shares its slug is another job's
  run "$SCRIPT" result "A job!"
  [ "$status" -eq 1 ]; [ -z "$output" ]
  # a log with no result: the run was cut short
  printf '# cut short\noutput\n' >"$LOGS/1790000200-cut-short.log"
  run "$SCRIPT" result "cut short"
  [ "${lines[0]}" = "gone from pending.txt, no result in its log" ]
  run "$SCRIPT" result "never queued"
  [ "$status" -eq 1 ]
}

@test "status: read-only, naming what failed, what has waited, lines of no job, and the logs" {
  add 1790000000 run "old one" "echo old"
  add 1790700000 run "broke" "false"
  add 1790700100 run "did it" "true"
  add 1790700200 hand "a step" "# x"
  add 1790700300 message "post it" "text"
  TZ=UTC NOW=1790700400 "$SCRIPT" ran "broke" 2
  TZ=UTC NOW=1790700400 "$SCRIPT" ran "did it" 0
  printf 'loose\n' >"$BATS_TEST_TMPDIR/l"
  cat "$BATS_TEST_TMPDIR/l" "$PENDING" >"$BATS_TEST_TMPDIR/both"; cp "$BATS_TEST_TMPDIR/both" "$PENDING"
  mkdir -p "$LOGS"; : >"$LOGS/1-stray.log"; : >"$LOGS/orphans.txt"
  cp "$PENDING" "$BATS_TEST_TMPDIR/before"
  run env NOW=1790700500 "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' "$PENDING: 2 waiting, 1 ran ok, 1 failed, 1 by hand" \
    '[ !! ] failed: broke (#  ran Tue 29 Sep, 4:46pm: failed (exit 2))' \
    '[ !! ] waiting 8 days: old one' \
    '[ !! ] 1 line(s) with no job: the next change moves them out' \
    'logs: 1, 1 with no job in the file (kept 14 days)' \
    "orphans: $LOGS/orphans.txt (kept 14 days)")" ]
  cmp "$PENDING" "$BATS_TEST_TMPDIR/before"
  rm "$PENDING"
  rm -r "$LOGS"
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$PENDING: 0 waiting, 0 ran ok, 0 failed, 0 by hand" ]
  [ ! -e "$PENDING" ]
}

@test "a change that changes nothing leaves the file's time alone (an open Neovim isn't told it changed)" {
  add 1790000000 run "w" "c"
  touch -t 202001010000 "$PENDING"
  "$SCRIPT" tidy
  add 1790000900 run "w" "c"
  [ -z "$(find "$PENDING" -newermt 2021-01-01)" ]
}


@test "version" {
  run "$SCRIPT" version
  [ "$status" -eq 0 ]; [ "$output" = "pending 1.0.0" ]
}

# ------------------------------------------------------- writers at one moment
@test "writers at the same moment lose nothing, and leave no lock or temp file" {
  local i
  for i in $(seq 1 16); do NOW=$((1790000000 + i)) "$SCRIPT" add run "job $i" "cmd $i" & done
  wait
  [ "$(grep -c '^# ' "$PENDING")" -eq 16 ]
  for i in $(seq 1 8); do "$SCRIPT" remove "job $i" & done
  wait
  [ "$(grep -c '^# ' "$PENDING")" -eq 8 ]
  run bash -c "ls -A '$BATS_TEST_TMPDIR' | grep -c 'pending.txt\\.'"
  [ "$output" = 0 ]
}

@test "a lock held makes a writer wait, a killed run's is taken over, and a failed change leaves none" {
  mkdir "$PENDING.lock"
  ( sleep 0.5; rmdir "$PENDING.lock" ) &
  add 1790000000 run "after the wait" "a"
  wait
  grep -q 'after the wait' "$PENDING"
  [ ! -e "$PENDING.lock" ]
  mkdir "$PENDING.lock"
  touch -t 202001010000 "$PENDING.lock"
  add 1790000000 run "after a killed run" "b"
  grep -q 'after a killed run' "$PENDING"
  [ ! -e "$PENDING.lock" ]
  run "$SCRIPT" ran "nothing" 0
  [ "$status" -ne 0 ]
  [ ! -e "$PENDING.lock" ]
  # readers take no lock
  mkdir "$PENDING.lock"
  run "$SCRIPT" show
  [ "$status" -eq 0 ]
  run "$SCRIPT" has "after a killed run"
  [ "$status" -eq 0 ]
  rmdir "$PENDING.lock"
}

@test "a folder for pending.txt is made; one it can't write in is said at once" {
  local nested=$BATS_TEST_TMPDIR/new/folder/pending.txt
  PENDING=$nested NOW=1790000000 "$SCRIPT" add run "w" "c"
  grep -q 'run: w' "$nested"
  mkdir "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  # root can write anywhere
  if [[ ! -w $BATS_TEST_TMPDIR/ro ]]; then
    PENDING=$BATS_TEST_TMPDIR/ro/p.txt run "$SCRIPT" add run "w" "c"
    [ "$status" -ne 0 ]; [ "$output" = "pending: can't write in $BATS_TEST_TMPDIR/ro" ]
  fi
  chmod 700 "$BATS_TEST_TMPDIR/ro"
}


@test "pending.txt is ~/pending.txt on the rig, ~/x/pending.txt on the Mac" {
  local home=$BATS_TEST_TMPDIR/home
  mkdir -p "$home/x" "$BATS_TEST_TMPDIR/mac" "$BATS_TEST_TMPDIR/linux"
  printf '#!/bin/sh\necho Darwin\n' >"$BATS_TEST_TMPDIR/mac/uname"
  printf '#!/bin/sh\necho Linux\n' >"$BATS_TEST_TMPDIR/linux/uname"
  chmod +x "$BATS_TEST_TMPDIR/mac/uname" "$BATS_TEST_TMPDIR/linux/uname"
  HOME=$home PENDING='' PATH=$BATS_TEST_TMPDIR/linux:$PATH "$SCRIPT" add run "Here" "true"
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
  run grep -niE 'proton|google|gcp|youtube|github|gitlab|nord|bitwarden|authy|whatsapp|chromium|herdr|LINE[0-9]|@[a-z0-9-]+\.(com|me|net|co)([^[:alnum:]_]|$)' "$BATS_TEST_FILENAME"
  # this test's own pattern is the one match allowed
  [ "${#lines[@]}" -eq 1 ]
}
