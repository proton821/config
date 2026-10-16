#!/usr/bin/env bash
# pending.sh - the one way ~/pending.txt is changed, by Claude and by timers
# alike. The layout below is the spec (~/.claude/CLAUDE.md, "Commands I run
# myself", says what goes in the queue and points here for how it looks;
# why: ~/ops/scripts-first/README.md, "pending.sh"):
#
#   # <epoch> <type>: <what it does, to jog the memory>
#   #  <a note: a password to look up, what to do if it stops>
#   <the command, at column 0>
#
#   ------------------------------------------------------------------------
#
#   <what to do by hand, as prose that runs on from line to line, wrapped
#   at 72 characters, with no prefix>
#
#   * the file is 72 characters wide: the line is 72 hyphens, an added
#     job's head line, notes and commands fit in 72 (add refuses one that
#     doesn't), and by-hand prose is wrapped at 72 (a word longer than that
#     stands on a line of its own); a message's own lines are as given;
#   * every job above the line is one head line, then any "#  " notes and
#     command lines, in the order given; all but the commands are shell
#     comments, so pasting a whole job runs only them;
#   * a "message" job (a Slack message, a Jira or PR comment to post) is its
#     head line, then the message exactly as given, to be yanked whole into
#     the app: any number of lines of any length, blank lines and "#" lines
#     too, no notes; it ends at the next job's head line or the line, and
#     add refuses a message holding either; its lines are never commands;
#   * the head line says, after the "#", when it was queued, then the type
#     (what the user has to type, such as which password) and what it does;
#   * "hand" jobs are prose, so they go below the line (a blank line
#     either side, there only when one waits), each one paragraph: its what,
#     then its lines (a note's "#" dropped), each run on after a ". " (or a
#     space, after one that ends . : ; ? or !), with no type and no epoch;
#   * the epoch is the plain integer (seconds since the epoch), nothing
#     around it;
#   * the type is what the user has to type or do, as short as it can be:
#     "run" (a command, no password), "sudo", "sudo + PIN", "other
#     password", "block" (a command Claude's sandbox blocked), "boot" (a
#     reboot), "hand" (a step in an app), "live" (a running job's status
#     command), "message" (text to post); its first letter lower case; its words are
#     single-spaced, none is only digits and none has a ":", so the type
#     ends at the first ": ";
#   * an older, longer type is shortened wherever it is read or added: a
#     trailing "(...)" goes, "rig password" is "sudo", " and " is " + ",
#     and "no password", "reboot", "by hand" and "running" are "run",
#     "boot", "hand" and "live" ("Rig password (sudo)" is "sudo", "Rig
#     password and PIN" is "sudo + PIN", "No password (auto mode blocks
#     Claude)" is "run");
#   * one blank line between jobs; nothing else in the file, and 0 bytes when
#     nothing waits;
#   * jobs newest first by their epoch (ties keep their order: numbered
#     steps); the epoch is when the job was first queued: the same job
#     twice (type, what and lines) is kept once, at its oldest time; below
#     the line, newest first too: a new job goes on top, and the same job
#     again stays where it is;
#   * a job is known by its what: remove and has match it exactly, or by its
#     start with --prefix; a by-hand job says WHAT when its prose is WHAT
#     or starts with WHAT and the ". " (or space) after it.
#
# Every change re-reads the file and rewrites it whole, atomically. A file
# it can't read is left alone, with the job it stopped at named. A job in
# an older layout is read and written back in this one: v3's head
# "# type epoch what", v2's "# type `date -d @epoch` what", or v1's
# "#= type", "#@ ISO time · session · from", "#> what". Lines already
# wider than 72 are read and kept as they are.
#
# This script and pending.bats are the spec for pending.bin (pending.rust/):
# change them first, then the Rust; ~/scripts/rust/rust.sh builds it.
#
# Runs on Linux and macOS: bash 5 (Homebrew's on macOS, whose own is 3.2),
# and GNU or BSD date, stat and chmod.
#
# Usage:
#   pending.sh add TYPE WHAT LINE...        a new job, stamped now; a LINE
#                                           "# text" is a note
#   pending.sh add message WHAT [LINE...]   a message: the LINEs as given,
#                                           or stdin's text with none
#   pending.sh remove [--prefix] WHAT       the jobs saying WHAT (or starting
#                                           with it)
#   pending.sh has [--prefix] WHAT          exit 0 if such a job exists
#   pending.sh tidy                         rewrite in order, nothing else
#   pending.sh show [WHAT...]               the head lines (no notes or
#                                           commands), newest first, then the
#                                           line and the by-hand prose: every
#                                           job's, or only those saying a WHAT;
#                                           how Claude ends a reply
#   pending.sh match LINE                   the job whose command LINE is:
#                                           "EPOCH<TAB>WHAT"; exit 1 if none
#                                           (or LINE shows a secret)
#   pending.sh ran WHAT EXIT                mark the job: a first note
#                                           "#  ran DAY D MON, TIME: ok" (or
#                                           "failed (exit N)"), replacing the
#                                           last one
#   pending.sh run LINE                     what pending-hook.sh runs when the
#                                           user runs a queued command: LINE
#                                           in bash, its output on screen and
#                                           kept in LOGS/EPOCH-what.log (tee),
#                                           then `ran`, and on a failure
#                                           "ERROR: WHAT failed (exit N)" last
#                                           on the terminal; exits as LINE
#                                           did, or 100 (nothing run) when
#                                           LINE is no job's
#
# A job's log is for Claude to read (the user runs, Claude checks); `remove`
# deletes it with the job. A line that prints a secret (secret.sh show) is
# never run here, so its output is never kept. The input stays the terminal
# (a password prompt reads it as before, and lines pasted after the command
# wait for the shell); the output goes through tee, so a program sees a pipe,
# not a terminal, and may print without colour.
set -euo pipefail
(( BASH_VERSINFO[0] >= 5 )) || { printf 'pending: needs bash 5 or later, not %s\n' "$BASH_VERSION" >&2; exit 1; }

# The queue: ~/x/pending.txt on the work Mac, ~/pending.txt elsewhere.
if [[ $(uname -s) == Darwin ]]; then MAC=1; else MAC=0; fi
if (( MAC )); then PENDING=${PENDING:-$HOME/x/pending.txt}; else PENDING=${PENDING:-$HOME/pending.txt}; fi
NOW=${NOW:-$(date +%s)}
LOGS=${LOGS:-$HOME/.local/state/pending}
NOT_A_JOB=100
# run's command: LINE ($1) in bash, its output both on screen and added to the
# log ($2); exits as LINE did. pending.bin runs the same text.
# shellcheck disable=SC2016 # expanded by the bash it is given to, not here
RUNNER='bash -c "$1" 2>&1 | tee -a "$2"; exit "${PIPESTATUS[0]}"'

# Widths are counted in characters, whatever the caller's locale (macOS has
# en_US.UTF-8, not C.UTF-8).
if (( MAC )); then export LC_ALL=en_US.UTF-8; else export LC_ALL=C.UTF-8; fi
# GNU date (Linux) reads a time with -d; BSD date (macOS) with -r or -j -f.
if date --version >/dev/null 2>&1; then GNU_DATE=1; else GNU_DATE=0; fi

die() { printf 'pending: %s\n' "$*" >&2; exit 1; }

# A word of a TYPE: no blank, no colon, not only digits.
TYPE_WORD='[^[:space:]:]*[^0-9[:space:]:][^[:space:]:]*'
TYPE_RE="^$TYPE_WORD( $TYPE_WORD)*\$"
HEAD_RE="^# ([0-9]+) ($TYPE_WORD( $TYPE_WORD)*): (.+)\$"
# v3's head: the type first (its words could hold a colon), then the epoch.
V3_WORD='[^[:space:]]*[^0-9[:space:]][^[:space:]]*'
V3_HEAD_RE="^# ($V3_WORD( $V3_WORD)*) ([0-9]+) (.+)\$"
# shellcheck disable=SC2016  # the backticks are literal text in a v2 head, not a command
V2_HEAD_RE='^# ([^`[:space:]][^`]*) `date -d @([0-9]+)` (.+)$'

# Below this line, the by-hand jobs, as prose; the file's width. A message
# job's lines are text to post.
HAND=hand
MESSAGE=message
WIDTH=72
SEP=$(printf '%.0s-' $(seq "$WIDTH"))

# The queue in memory: one entry per job, in file order.
J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=() ORDER=()

# short TYPE: TYPE as the queue writes it: first letter lower case, no
# trailing "(...)", "rig password" as "sudo", " and " as " + ".
short() {
  local t=${1,}
  [[ $t =~ ^(.*[^[:space:]])\ \([^()]*\)$ ]] && t=${BASH_REMATCH[1]}
  [[ $t == "rig password" || $t == "rig password "* ]] && t=sudo${t#rig password}
  t=${t// and / + }
  case $t in
    "no password") t=run ;;
    reboot) t=boot ;;
    "by hand") t=$HAND ;;
    running) t=live ;;
  esac
  printf '%s' "$t"
}

# v1_epoch STAMP: a v1 "#@" time (with its offset, or Z; a bare date is
# midnight UTC) as seconds since the epoch; 0 if it isn't such a time.
v1_epoch() {
  local s
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z))?$ ]] || { echo 0; return; }
  if [[ $1 == *T* ]]; then s=$1; else s="$1T00:00:00Z"; fi
  if (( GNU_DATE )); then date -d "$s" +%s 2>/dev/null || echo 0; return; fi
  # BSD: the time as UTC, then its offset taken off.
  local secs off=${s:19}
  secs=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${s:0:19}" +%s 2>/dev/null) || { echo 0; return; }
  if [[ $off =~ ^([+-])([0-9]{2}):([0-9]{2})$ ]]; then
    secs=$((secs - ${BASH_REMATCH[1]}1 * (10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60)))
  fi
  echo "$secs"
}

# words TEXT: TEXT's words, one space between them.
words() {
  local -a w
  read -ra w <<<"$1"
  printf '%s' "${w[*]}"
}

# after TEXT: what runs on after TEXT: a space if it ends . : ; ? or !, else
# ". ".
after() { if [[ $1 =~ [.:\;?!]$ ]]; then printf ' '; else printf '. '; fi; }

# prose WHAT BODY: a by-hand job as one paragraph: WHAT, then each line of
# BODY (a note's "#" and the blanks after it dropped) run on after it.
prose() {
  local line out
  out=$(words "$1")
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    [[ $line =~ ^#[[:space:]]+(.*)$ ]] && line=${BASH_REMATCH[1]}
    line=$(words "$line")
    [[ -n $line ]] || continue
    out+=$(after "$out")$line
  done <<<"$2"
  printf '%s' "$out"
}

# push TYPE EPOCH WHAT BODY: a by-hand job's WHAT becomes its whole
# paragraph, its BODY nothing.
push() {
  local type what=$3 body=$4
  type=$(short "$1")
  if [[ $type == "$HAND" ]]; then what=$(prose "$what" "$body") body=""; fi
  J_TYPE+=("$type") J_EPOCH+=("$2") J_WHAT+=("$what") J_BODY+=("$body")
}

# load: the file into J_*; dies (nothing written) on a job it can't read.
load() {
  local line n=0 lineno=0 at=0 type="" epoch="" what="" body="" v1=0 stamp="" below=0 msg=0 g
  local -a gap=()
  J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=()
  [[ -f $PENDING ]] || return 0
  finish() {
    (( n )) || return 0
    if (( v1 )); then
      [[ -n $stamp && -n $what ]] || die "$PENDING: the job at line $at has no #=, #@ or #> line; nothing changed"
      [[ $stamp == *' · '*' · '* ]] || die "$PENDING: line $((at + 1)): '#@' is TIME · SESSION · FROM; nothing changed"
      epoch=$(v1_epoch "${stamp%%' · '*}")
    fi
    push "$type" "$epoch" "$what" "$body"
    n=0 v1=0 type="" epoch="" what="" body="" stamp="" msg=0 gap=()
  }
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    # A message runs on, blank lines and all, to the next head line or the
    # line; blank lines at its end are the gap before them.
    if (( msg )); then
      if [[ $line != "$SEP" && ! $line =~ $HEAD_RE ]]; then
        if [[ -z ${line//[[:space:]]/} ]]; then gap+=("$line"); continue; fi
        for g in "${gap[@]}"; do body+=$'\n'$g; done
        gap=()
        body+=${body:+$'\n'}$line
        continue
      fi
      finish
    fi
    if [[ -z ${line//[[:space:]]/} ]]; then finish; continue; fi
    if [[ $line =~ ^-{3,}$ ]]; then finish; below=1; continue; fi
    (( n++ )) || at=$lineno
    if (( below )); then
      type=$HAND epoch=0 what+=${what:+ }$line
      continue
    fi
    if (( n == 1 )); then
      if [[ $line =~ $HEAD_RE ]]; then
        epoch=$((10#${BASH_REMATCH[1]})) type=${BASH_REMATCH[2]} what=${BASH_REMATCH[4]}
      elif [[ $line =~ $V2_HEAD_RE ]]; then
        type=${BASH_REMATCH[1]} epoch=$((10#${BASH_REMATCH[2]})) what=${BASH_REMATCH[3]}
      elif [[ $line =~ $V3_HEAD_RE ]]; then
        type=${BASH_REMATCH[1]} epoch=$((10#${BASH_REMATCH[3]})) what=${BASH_REMATCH[4]}
      elif [[ $line == "#= "* ]]; then
        v1=1 type=${line:3}
      else
        die "$PENDING: line $lineno: a job starts '# EPOCH TYPE: WHAT'; nothing changed"
      fi
      [[ $(short "$type") != "$MESSAGE" ]] || msg=1
      continue
    fi
    if (( v1 && n == 2 )); then
      [[ $line == "#@ "* ]] || die "$PENDING: line $lineno: '#@' is a v1 job's second line; nothing changed"
      stamp=${line:3}; continue
    fi
    if (( v1 && n == 3 )); then
      [[ $line == "#> "* ]] || die "$PENDING: line $lineno: '#>' is a v1 job's third line; nothing changed"
      what=${line:3}; continue
    fi
    body+=${body:+$'\n'}$line
  done <"$PENDING"
  finish
}

# ordered: ORDER, the indexes of J_* newest first (ties in file order), the
# same job twice once, at its oldest time (the earlier in the file on a tie).
ordered() {
  local i k id
  local -a sortkeys=()
  local -A keep=()
  ORDER=()
  for i in "${!J_TYPE[@]}"; do
    id=${J_TYPE[i]}$'\x1f'${J_WHAT[i]}$'\x1f'${J_BODY[i]}
    if [[ -z ${keep[$id]:-} ]] || (( J_EPOCH[i] < J_EPOCH[${keep[$id]}] )); then keep[$id]=$i; fi
  done
  for i in "${keep[@]}"; do
    sortkeys+=("$(printf '%020d %06d' $((99999999999 - J_EPOCH[i])) "$i")")
  done
  (( ${#sortkeys[@]} )) || return 0
  while IFS= read -r k; do ORDER+=($((10#${k##* }))); done < <(printf '%s\n' "${sortkeys[@]}" | LC_ALL=C sort)
}

# head_of I: job I's head line, without its newline.
head_of() {
  printf '# %d %s: %s' "${J_EPOCH[$1]}" "${J_TYPE[$1]}" "${J_WHAT[$1]}"
}

# wrap TEXT: TEXT on lines of at most WIDTH, broken at its spaces.
wrap() {
  local w line=""
  local -a ws
  read -ra ws <<<"$1"
  for w in "${ws[@]}"; do
    if [[ -z $line ]]; then line=$w
    elif (( ${#line} + 1 + ${#w} <= WIDTH )); then line+=" $w"
    else printf '%s\n' "$line"; line=$w
    fi
  done
  [[ -z $line ]] || printf '%s\n' "$line"
}

# below I...: the line, then each by-hand job I as its wrapped paragraph, a
# blank line before each.
below() {
  local i
  printf '%s\n' "$SEP"
  for i in "$@"; do printf '\n'; wrap "${J_WHAT[i]}"; done
}

# render: J_* in ORDER, to stdout: the by-hand jobs below the line.
render() {
  local i first=1
  local -a hand=()
  ordered
  for i in "${ORDER[@]}"; do
    if [[ ${J_TYPE[i]} == "$HAND" ]]; then hand+=("$i"); continue; fi
    (( first )) || printf '\n'
    first=0
    head_of "$i"; printf '\n'
    [[ -z ${J_BODY[i]} ]] || printf '%s\n' "${J_BODY[i]}"
  done
  (( ${#hand[@]} )) || return 0
  (( first )) || printf '\n'
  below "${hand[@]}"
}

# save: render into a temp file beside the queue, then replace it (only if
# it differs).
save() {
  local tmp
  touch "$PENDING"
  tmp=$(mktemp "$PENDING.XXXXXX")
  render >"$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$PENDING"; then rm -f "$tmp"; return 0; fi
  chmod "$(stat -c %a "$PENDING" 2>/dev/null || stat -f %Lp "$PENDING")" "$tmp"
  mv "$tmp" "$PENDING"
}

# one_line NAME VALUE: dies unless VALUE is one non-empty line.
one_line() {
  [[ -n $2 ]] || die "$1 can't be empty"
  [[ $2 != *$'\n'* ]] || die "$1 is one line"
}

# body_of LINE...: the job's lines, "# text" notes as "#  text"; dies on a
# bad one.
body_of() {
  local line out=""
  for line in "$@"; do
    [[ -n ${line//[[:space:]]/} && $line != *$'\n'* ]] || die "each LINE is one non-empty line"
    case $line in
      "# "*) line="#  ${line:2}" ;;
      "#"*)  die "a LINE starting # is a note: '# text'" ;;
    esac
    out+=${out:+$'\n'}$line
  done
  printf '%s' "$out"
}

# message_of LINE...: a message's text: the LINEs as given (stdin's text
# with none), without blank lines at either end; dies on an empty one, or
# one holding a line the queue would read as a job's head or the line.
message_of() {
  local text line
  if (( $# )); then text=$(printf '%s\n' "$@"); else text=$(cat); fi
  text=$(printf '%s\n' "$text" | awk 'NF { n = NR } { l[NR] = $0 } END { for (i = 1; i <= n; i++) if (s || l[i] ~ /[^[:space:]]/) { s = 1; print l[i] } }')
  [[ -n $text ]] || die "a message can't be empty"
  while IFS= read -r line; do
    [[ $line != "$SEP" && ! $line =~ $HEAD_RE ]] || die "a message's line would end it in the queue: $line"
  done <<<"$text"
  printf '%s' "$text"
}

# fits TYPE EPOCH WHAT BODY: dies unless a job above the line is WIDTH wide
# at most: its head line and every line of BODY (a message's own lines are
# as given).
fits() {
  local head line
  [[ $1 != "$HAND" ]] || return 0
  head="# $2 $1: $3"
  (( ${#head} <= WIDTH )) || die "the head line is ${#head} characters, over $WIDTH: shorten WHAT"
  [[ $1 != "$MESSAGE" ]] || return 0
  while IFS= read -r line; do
    (( ${#line} <= WIDTH )) || die "a LINE is ${#line} characters as written, over $WIDTH: $line"
  done <<<"$4"
}

cmd_add() {
  [[ $# -ge 2 ]] || die "usage: pending.sh add TYPE WHAT LINE..."
  local type=$1 what=$2 body
  shift 2
  one_line TYPE "$type"; one_line WHAT "$what"
  [[ $type =~ $TYPE_RE ]] || die "a TYPE is single-spaced words, none of them only digits or with a colon"
  [[ $NOW =~ ^[0-9]+$ ]] || die "NOW is seconds since the epoch"
  if [[ $(short "$type") == "$MESSAGE" ]]; then body=$(message_of "$@")
  else
    (( $# )) || die "usage: pending.sh add TYPE WHAT LINE..."
    body=$(body_of "$@")
  fi
  fits "$(short "$type")" "$((10#$NOW))" "$what" "$body"
  load
  push "$type" "$((10#$NOW))" "$what" "$body"
  save
}

# says PREFIX WHAT I: exit 0 if job I says WHAT (or starts with it, when
# PREFIX is 1); a by-hand job's paragraph says WHAT when it is WHAT or runs
# on from it.
says() {
  local what=$2 text=${J_WHAT[$3]}
  if (( $1 )); then [[ $text == "$what"* ]]; return; fi
  if [[ ${J_TYPE[$3]} == "$HAND" ]]; then
    what=$(words "$what")
    [[ $text == "$what" || $text == "$what$(after "$what")"* ]]
  else
    [[ $text == "$what" ]]
  fi
}

# what_args NAME ARGS...: sets PREFIX and WHAT from "[--prefix] WHAT".
what_args() {
  local name=$1; shift
  PREFIX=0
  if [[ ${1:-} == --prefix ]]; then PREFIX=1; shift; fi
  [[ $# -eq 1 && -n $1 ]] || die "usage: pending.sh $name [--prefix] WHAT"
  WHAT=$1
}

# slug TEXT: TEXT in lower case, every run of other characters a hyphen,
# none at either end, at most 48 characters.
slug() {
  local t=${1,,}
  t=$(printf '%s' "$t" | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  t=${t:0:48}
  printf '%s' "${t%-}"
}

# log_of I: job I's log file.
log_of() { printf '%s/%s-%s.log' "$LOGS" "${J_EPOCH[$1]}" "$(slug "${J_WHAT[$1]}")"; }

cmd_remove() {
  local i
  what_args remove "$@"
  [[ -f $PENDING ]] || return 0
  load
  local -a kept=() T E W B
  for i in "${!J_TYPE[@]}"; do
    if says "$PREFIX" "$WHAT" "$i"; then rm -f -- "$(log_of "$i")"; else kept+=("$i"); fi
  done
  T=("${J_TYPE[@]}") E=("${J_EPOCH[@]}") W=("${J_WHAT[@]}") B=("${J_BODY[@]}")
  J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=()
  for i in "${kept[@]}"; do
    J_TYPE+=("${T[i]}") J_EPOCH+=("${E[i]}") J_WHAT+=("${W[i]}") J_BODY+=("${B[i]}")
  done
  save
}

cmd_has() {
  local i
  what_args has "$@"
  [[ -f $PENDING ]] || return 1
  load
  for i in "${!J_TYPE[@]}"; do
    says "$PREFIX" "$WHAT" "$i" && return 0
  done
  return 1
}

# wanted I WHAT...: exit 0 if job I says one of the WHATs, or none is given.
wanted() {
  local i=$1 w
  shift
  (( $# )) || return 0
  for w in "$@"; do says 0 "$w" "$i" && return 0; done
  return 1
}

# show [WHAT...]: the head lines in ORDER, every job's or only those saying
# one of the WHATs, then the line and the by-hand prose as the file has it;
# nothing for a missing queue.
cmd_show() {
  local i
  local -a hand=()
  [[ -f $PENDING ]] || return 0
  load
  ordered
  for i in "${ORDER[@]}"; do
    wanted "$i" "$@" || continue
    if [[ ${J_TYPE[i]} == "$HAND" ]]; then hand+=("$i"); continue; fi
    head_of "$i"; printf '\n'
  done
  (( ${#hand[@]} )) || return 0
  below "${hand[@]}"
}

# runs I LINE: exit 0 if LINE is one of job I's commands (not a note).
runs() {
  local l
  [[ ${J_TYPE[$1]} != "$HAND" && ${J_TYPE[$1]} != "$MESSAGE" ]] || return 1
  while IFS= read -r l; do
    [[ $l != "#"* && $l == "$2" ]] && return 0
  done <<<"${J_BODY[$1]}"
  return 1
}

# find_line LINE: sets FOUND to the first job, newest first, that runs LINE.
find_line() {
  local i
  FOUND=""
  [[ $1 != *secret.sh\ show* ]] || return 1
  [[ -f $PENDING ]] || return 1
  load
  ordered
  for i in "${ORDER[@]}"; do
    if runs "$i" "$1"; then FOUND=$i; return 0; fi
  done
  return 1
}

cmd_match() {
  [[ $# -eq 1 && -n $1 ]] || die "usage: pending.sh match LINE"
  find_line "$1" || return 1
  printf '%s\t%s\n' "${J_EPOCH[FOUND]}" "${J_WHAT[FOUND]}"
}

# when: NOW as the ran note writes it: "Thu 8 Oct, 9:14pm" (BSD date has no
# %P, so its AM or PM is lowered here).
when() {
  local t
  if (( GNU_DATE )); then LC_TIME=C date -d "@$NOW" '+%a %-d %b, %-I:%M%P'; return; fi
  t=$(LC_TIME=C date -r "$NOW" '+%a %-d %b, %-I:%M%p')
  t=${t/%AM/am}
  printf '%s\n' "${t/%PM/pm}"
}

cmd_ran() {
  [[ $# -eq 2 && -n $1 ]] || die "usage: pending.sh ran WHAT EXIT"
  [[ $2 =~ ^[0-9]+$ ]] || die "EXIT is a number"
  local i l note found=0 body
  if (( 10#$2 == 0 )); then note="#  ran $(when): ok"
  else note="#  ran $(when): failed (exit $((10#$2)))"; fi
  [[ -f $PENDING ]] || die "no job says: $1"
  load
  for i in "${!J_TYPE[@]}"; do
    [[ ${J_TYPE[i]} != "$HAND" && ${J_TYPE[i]} != "$MESSAGE" && ${J_WHAT[i]} == "$1" ]] || continue
    found=1 body=$note
    while IFS= read -r l; do
      [[ -n $l && $l != "#  ran "* ]] && body+=$'\n'$l
    done <<<"${J_BODY[i]}"
    J_BODY[i]=$body
  done
  (( found )) || die "no job says: $1"
  save
}

cmd_run() {
  [[ $# -eq 1 && -n $1 ]] || die "usage: pending.sh run LINE"
  local log rc=0 what
  find_line "$1" || return "$NOT_A_JOB"
  what=${J_WHAT[FOUND]} log=$(log_of "$FOUND")
  mkdir -p "$LOGS"; chmod 700 "$LOGS"
  printf '# %s\n' "$what" >"$log"
  bash -c "$RUNNER" pending "$1" "$log" || rc=$?
  cmd_ran "$what" "$rc"
  # A failure is easy to see at a glance; the terminal only, not the log.
  (( rc == 0 )) || printf 'ERROR: %s failed (exit %d)\n' "$what" "$rc" >&2
  return "$rc"
}

main() {
  local cmd=${1:-}; shift || true
  case $cmd in
    add)     cmd_add "$@" ;;
    remove)  cmd_remove "$@" ;;
    has)     cmd_has "$@" ;;
    tidy)    [[ -f $PENDING ]] || return 0; load; save ;;
    show)    cmd_show "$@" ;;
    match)   cmd_match "$@" ;;
    ran)     cmd_ran "$@" ;;
    run)     cmd_run "$@" ;;
    *) die "usage: pending.sh add|remove|has|tidy|show|match|ran|run (see the top of this file)" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
