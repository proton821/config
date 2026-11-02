#!/usr/bin/env bash
# pending.sh - the one way pending.txt is changed, by Claude and by timers
# alike (where it is: PENDING, below). The layout below is the spec
# (Claude's instructions, "Commands I run myself", say what goes in
# pending.txt and point here for how it looks):
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
#   * the file is 72 characters wide for what a job is: the line is 72
#     hyphens, an added job's head line and notes fit in 72 (add refuses
#     one that doesn't), and by-hand prose is wrapped at 72 (a word longer
#     than that stands on a line of its own); a command, and a message's
#     own lines, are as long as they are;
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
#     "run" (a command), "block" (a command Claude's sandbox blocked),
#     "hand" (a step in an app), "message" (text to post);
#     its first letter lower case; its words are single-spaced, none is
#     only digits and none has a ":", so the type ends at the first ": ";
#   * one blank line between jobs; nothing else in the file, and 0 bytes when
#     nothing waits;
#   * the most recently added job is on top: newest first by epoch, and in
#     the same second the one added last first; the epoch is when the job
#     was first queued: the same job twice (type, what and lines) is kept
#     once, at its oldest time, and queued again it loses its "ran" mark;
#     below the line, newest first too: a new job goes on top, and the same
#     job again stays where it is;
#   * a chain is the steps of one piece of work: each WHAT is NAME N/M and
#     what the step does, the same NAME and M in every step ("root tools
#     1/2: read the diff"); its steps stay together in step order, at the
#     place of the newest of them, however they were queued; add refuses a
#     first step with no NAME, since nameless chains can't be told apart.
#     N/M is the first such pair in the WHAT, N at most M, 1 to 99, M at
#     least 2, after a space or ( or [ or at the start, before a space, one
#     of : , ; . ) ] or the end ("24/7" is no step). A second chain of the
#     same NAME and M starts where a step number comes round again, taking
#     the steps by when they were queued;
#   * a job is known by its what: remove and has match it exactly (blanks
#     as single spaces), or by its start with --prefix; a by-hand job says
#     WHAT when its prose is WHAT or starts with WHAT and the ". " (or
#     space) after it.
#
# Every change takes a lock (PENDING.lock, a folder; one left by a killed
# run is taken over after 30 seconds), re-reads the file and rewrites it
# whole, atomically, so writers at the same moment lose nothing. Readers
# need no lock. Lines already wider than 72 are read and kept as they are.
#
# The user edits the file by hand too, and only deletes (ggdG, d4<CR>), so
# reading never refuses a file:
#   * a head line starts a job wherever it stands, even with no blank line
#     before it, or below the line;
#   * the line is still the line with hyphens gone from it (three or more and
#     nothing else), or, outside a job, with stray characters in it (half its
#     hyphens or more);
#   * a line above the line that belongs to no job (a job's notes or command
#     whose head line was cut, or anything typed) is left out of the queue:
#     reading ignores it, and the next change moves it to LOGS/orphans.txt
#     (dated, saying so on stderr), as it does a head line left with no
#     lines after it. Nothing that was in the file is lost, and nothing is
#     left to trim by hand;
#   * a job gone by hand is simply gone: `run` still ends as its command
#     did, and its log goes as the logs below do.
#
# A job stays until it is removed or cut: one that ran keeps its mark, ok or
# failed, and one never run waits (status names what failed and, after 7 days,
# what never ran). Only these go by themselves, at any change (and each new
# shell tidies, from the hook):
#   * a log with no job, and orphans.txt, after 14 days untouched.
#
#
# Runs on Linux and macOS: bash 5 (Homebrew's on macOS, whose own is 3.2),
# and GNU or BSD date, stat, chmod, find and tee.
#
# Usage:
#   pending.sh add TYPE WHAT LINE...        a new job, stamped now; a LINE
#                                           "# text" is a note; blanks around
#                                           a command go
#   pending.sh add message WHAT [LINE...]   a message: the LINEs as given,
#                                           or stdin's text with none
#   pending.sh remove [--prefix] WHAT       the jobs saying WHAT (or starting
#                                           with it), and their logs
#   pending.sh has [--prefix] WHAT          exit 0 if such a job exists
#   pending.sh tidy                         rewrite in order, moving out what
#                                           has no job (above)
#   pending.sh show [WHAT...]               the head lines (no notes or
#                                           commands), newest first, then the
#                                           line and the by-hand prose: every
#                                           job's, or only those saying a WHAT;
#                                           how Claude ends a reply
#   pending.sh result WHAT                  how the job stands: "waiting", or
#                                           its mark; a job gone from the file
#                                           is answered from its log. Then
#                                           "log: PATH" if it has one; exit 1
#                                           if nothing is known of it
#   pending.sh status                       read-only: what waits, what failed,
#                                           what has waited over 7 days, lines
#                                           with no job, logs, orphans
#   pending.sh version                      this version
#   pending.sh match LINE                   the job whose command LINE is:
#                                           "EPOCH<TAB>WHAT"; exit 1 if none
#   pending.sh ran WHAT EXIT                mark the job: a first note
#                                           "#  ran DAY D MON, TIME: ok" (or
#                                           "failed (exit N)"), replacing the
#                                           last one
#   pending.sh run LINE                     what the shell's hook runs when
#                                           the user runs a job's command: LINE
#                                           in bash, its output on screen and
#                                           kept in LOGS/EPOCH-what.log (tee),
#                                           then the mark, in the file and last
#                                           in the log, on the one job that
#                                           runs LINE, and on a failure "ERROR:
#                                           WHAT failed (exit N)" last on the
#                                           terminal. It exits as LINE did (but
#                                           for LINE's own 100, which comes back
#                                           as 1: the mark has the real one), or
#                                           100 with nothing run when LINE is
#                                           no job's or no log can be kept, so
#                                           the shell runs it as usual
#   pending.sh ended LOG WHAT LINE EXIT     how `run` ends, once LINE has
#
# A job's log is for Claude to read (the user runs, Claude checks); `remove`
# deletes it with the job.
# The input stays the terminal
# (a password prompt reads it as before, and lines pasted after the command
# wait for the shell); the output goes through tee, so a program sees a pipe,
# not a terminal, and may print without colour. Ctrl-C reaches the command,
# and the job is still marked. A background process the command leaves
# holding its output doesn't hold the prompt (tee is waited for 2 seconds).
# The command runs in the caller's own locale.
# shellcheck disable=SC2310  # says, wanted, runs, step_of, find_line, mark and the like are tests: their status is the answer
# shellcheck disable=SC2312  # each $(...) left is words, an epoch for a message, or a log's name: nothing that fails there can stop what matters
set -euo pipefail
(( BASH_VERSINFO[0] >= 5 )) || { printf 'pending: needs bash 5 or later, not %s\n' "$BASH_VERSION" >&2; exit 1; }

VERSION=1.0.0
# Where pending.txt is: ~/x/pending.txt on the Mac, ~/pending.txt on the rig.
KERNEL=$(uname -s)
if [[ $KERNEL == Darwin ]]; then MAC=1; else MAC=0; fi
if (( MAC )); then PENDING=${PENDING:-$HOME/x/pending.txt}; else PENDING=${PENDING:-$HOME/pending.txt}; fi
# (PENDING is set only by the tests.)
LOCK=$PENDING.lock
NOW=${NOW:-$(date +%s)}
LOGS=${LOGS:-$HOME/.local/state/pending}
ORPHANS=$LOGS/orphans.txt
NOT_A_JOB=100
LOCK_STALE=30
STALE_DAYS=7
KEEP_DAYS=14
# run's command: LINE ($1) in bash, its output both on screen and added to the
# log ($2), then ($4...) `ended`, as this script's own command; the shell stays
# for a Ctrl-C the command takes, and tee ignores it, to log what comes after.
# shellcheck disable=SC2016 # expanded by the bash it is given to, not here
RUNNER='trap : INT TERM HUP
bash -c "$1" > >(tee -ai "$2") 2>&1
rc=$?
t=$!
for (( i = 0; i < 40; i++ )); do
  kill -0 "$t" 2>/dev/null || break
  sleep 0.05
done
exec "${@:4}" ended "$2" "$3" "$1" "$rc"'

# Widths are counted in characters, whatever the caller's locale (macOS has
# en_US.UTF-8, not C.UTF-8); `run` gives the command the caller's back.
CALLER_LC_ALL=${LC_ALL-} CALLER_HAD_LC_ALL=${LC_ALL+1}
if (( MAC )); then export LC_ALL=en_US.UTF-8; else export LC_ALL=C.UTF-8; fi
# GNU date (Linux) reads a time with -d; BSD date (macOS) with -r.
if date --version >/dev/null 2>&1; then GNU_DATE=1; else GNU_DATE=0; fi

die() { printf 'pending: %s\n' "$*" >&2; exit 1; }

# What counts as a blank: ASCII alone, whatever the locale says of Unicode
# spaces.
SP=$' \t\r\v\f'
# A word of a TYPE: no blank, no colon, not only digits.
TYPE_WORD="[^$SP:]*[^0-9$SP:][^$SP:]*"
TYPE_RE="^$TYPE_WORD( $TYPE_WORD)*\$"
HEAD_RE="^# ([0-9]{1,18}) ($TYPE_WORD( $TYPE_WORD)*): (.+)\$"
PAREN_RE="^(.*[^$SP]) \\([^()]*\\)\$"
# A chain's step, as the top of this file says: N, M and what's either side.
STEP_RE='(^|[ ([])([1-9][0-9]?)/([1-9][0-9]?)($|[] :,;.)])'
# The mark `ran` writes, as a job's first line.
MARK_AT='^#  ran [A-Z][a-z]{2} [0-9]{1,2} [A-Z][a-z]{2}, [0-9]{1,2}:[0-9]{2}[ap]m: '
MARK_RE=$MARK_AT'(ok|failed \(exit [0-9]+\))$'
OK_RE=$MARK_AT'ok$'

# Below this line, the by-hand jobs, as prose; the file's width. A message
# job's lines are text to post.
HAND=hand
MESSAGE=message
WIDTH=72
SEP=$(printf '%.0s-' $(seq "$WIDTH"))

# pending.txt in memory: one entry per job, in file order, and the lines that
# belong to none.
J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=() ORDER=() LOOSE=()

# short TYPE: TYPE as pending.txt has it: first letter lower case, no
# trailing "(...)", " and " as " + ".
short() {
  local t=${1,}
  if [[ $t =~ $PAREN_RE ]]; then t=${BASH_REMATCH[1]}; fi
  t=${t// and / + }
  SHORT=$t
}

# words TEXT: sets WORDS to TEXT's words, one space between them.
words() {
  local -a w
  read -ra w <<<"$1"
  WORDS=${w[*]}
}

# after TEXT: what runs on after TEXT: a space if it ends . : ; ? or !, else
# ". ".
after() { if [[ $1 =~ [.:\;?!]$ ]]; then AFTER=' '; else AFTER='. '; fi; }

# prose WHAT BODY: sets PROSE to a by-hand job as one paragraph: WHAT, then
# each line of BODY (a note's "#" and the blanks after it dropped) run on
# after it.
prose() {
  local line out
  words "$1"; out=$WORDS
  while IFS= read -r line; do
    if [[ $line == "#"[$SP]* ]]; then line=${line#\#}; line=${line#"${line%%[!"$SP"]*}"}; fi
    words "$line"; line=$WORDS
    [[ -n $line ]] || continue
    after "$out"
    out+=$AFTER$line
  done <<<"$2"
  PROSE=$out
}

# job TYPE WHAT BODY: sets N_TYPE, N_WHAT and N_BODY to the job as the queue
# holds it: a by-hand job's WHAT is its whole paragraph, its BODY nothing.
job() {
  short "$1"
  N_TYPE=$SHORT N_WHAT=$2 N_BODY=$3
  if [[ $N_TYPE == "$HAND" ]]; then prose "$2" "$3"; N_WHAT=$PROSE N_BODY=""; fi
}

push() {
  job "$1" "$3" "$4"
  J_TYPE+=("$N_TYPE") J_EPOCH+=("$2") J_WHAT+=("$N_WHAT") J_BODY+=("$N_BODY")
}

# unmarked BODY: sets UNMARKED to BODY without its mark.
unmarked() {
  UNMARKED=$1
  [[ ${1%%$'\n'*} =~ $MARK_RE ]] || return 0
  if [[ $1 == *$'\n'* ]]; then UNMARKED=${1#*$'\n'}; else UNMARKED=""; fi
}

# load: the file into J_*, and what belongs to no job into LOOSE.
load() {
  local line state="" type="" epoch="" what="" body="" below=0 msg=0 g h_epoch h_type h_what hyphens
  local -a gap=()
  J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=() LOOSE=()
  [[ -f $PENDING ]] || return 0
  finish() {
    case $state in
      job)
        unmarked "$body"
        short "$type"
        if [[ -n $UNMARKED || $SHORT == "$HAND" ]]; then push "$type" "$epoch" "$what" "$body"
        else
          # A head line with nothing of its job left.
          LOOSE+=("# $epoch $type: $what")
          if [[ -n $body ]]; then LOOSE+=("$body"); fi
        fi ;;
      hand) push "$HAND" 0 "$what" "" ;;
    esac
    state="" type="" epoch="" what="" body="" msg=0 gap=()
  }
  while IFS= read -r line || [[ -n $line ]]; do
    # A message runs on, blank lines and all, to the next head line or the
    # line; blank lines at its end are the gap before them.
    if (( msg )); then
      if [[ $line != "$SEP" && ! $line =~ $HEAD_RE ]]; then
        if [[ -z ${line//[$SP]/} ]]; then gap+=("$line"); continue; fi
        if [[ -n $body ]]; then for g in "${gap[@]}"; do body+=$'\n'$g; done; fi
        gap=()
        body+=${body:+$'\n'}$line
        continue
      fi
      finish
    fi
    if [[ -z ${line//[$SP]/} ]]; then finish; continue; fi
    if [[ $line == "$SEP" ]] || { (( ! below )) && [[ $line =~ ^-{3,}$ ]]; }; then finish; below=1; continue; fi
    if [[ $line =~ $HEAD_RE ]]; then
      h_epoch=${BASH_REMATCH[1]} h_type=${BASH_REMATCH[2]} h_what=${BASH_REMATCH[4]}
      finish
      epoch=$((10#$h_epoch)) type=$h_type what=$h_what state=job
      short "$type"
      if [[ $SHORT == "$MESSAGE" ]]; then msg=1; fi
      continue
    fi
    case $state in
      job) body+=${body:+$'\n'}$line ;;
      hand) what+=" $line" ;;
      *)
        hyphens=${line//[^-]/}
        if (( below )); then state=hand what=$line
        elif (( ${#hyphens} >= WIDTH / 2 )); then below=1
        else LOOSE+=("$line"); fi ;;
    esac
  done <"$PENDING"
  finish
}

# step_of WHAT: sets S_NAME (all before N), S_N and S_M from WHAT's step; exit
# 1 if it has none.
step_of() {
  local rest=$1 before="" all lead tail n m pre
  while [[ $rest =~ $STEP_RE ]]; do
    all=${BASH_REMATCH[0]} lead=${BASH_REMATCH[1]} n=${BASH_REMATCH[2]} m=${BASH_REMATCH[3]} tail=${BASH_REMATCH[4]}
    pre=${rest%%"$all"*}
    if (( n <= m && m >= 2 )); then
      S_NAME=$before$pre$lead S_N=$n S_M=$m
      return 0
    fi
    before+=$pre$lead$n/$m
    rest=$tail${rest#*"$all"}
  done
  return 1
}

# ordered: ORDER, the indexes of J_* newest first (ties in file order), the
# same job twice once, at its oldest time (the earlier in the file on a tie);
# a chain's steps together, in step order, where the newest of them would be.
ordered() {
  local i k id set c found sorted chains=0
  local -a keys=() steps=() chain=() step=()
  local -A keep=() set_epoch=() set_first=() name=() have=() of=()
  ORDER=()
  for i in "${!J_TYPE[@]}"; do
    unmarked "${J_BODY[i]}"
    id=${J_TYPE[i]}$'\x1f'${J_WHAT[i]}$'\x1f'$UNMARKED
    if [[ -z ${keep[$id]:-} ]] || (( J_EPOCH[i] < J_EPOCH[${keep[$id]}] )); then keep[$id]=$i; fi
  done
  for i in "${keep[@]}"; do
    chain[i]=i$i step[i]=0
    if step_of "${J_WHAT[i]}"; then
      step[i]=$S_N name[$i]=$S_NAME/$S_M
      printf -v k '%018d %06d' "${J_EPOCH[i]}" "$i"
      steps+=("$k")
    fi
  done
  # Steps by when they were queued, each to the newest chain of its name
  # still lacking that step.
  if (( ${#steps[@]} )); then
    sorted=$(printf '%s\n' "${steps[@]}" | LC_ALL=C sort)
    while IFS= read -r k; do
      i=$((10#${k##* })) found=""
      for c in ${of[${name[$i]}]:-}; do
        if [[ -z ${have[$c.${step[i]}]:-} ]]; then found=$c; break; fi
      done
      if [[ -z $found ]]; then
        found=$chains chains=$((chains + 1))
        of[${name[$i]}]="$found ${of[${name[$i]}]:-}"
      fi
      have[$found.${step[i]}]=1
      chain[i]=c$found
    done <<<"$sorted"
  fi
  for i in "${keep[@]}"; do
    set=${chain[i]}
    if [[ -z ${set_epoch[$set]:-} ]] || (( J_EPOCH[i] > set_epoch[$set] )); then set_epoch[$set]=${J_EPOCH[i]}; fi
    if [[ -z ${set_first[$set]:-} ]] || (( i < set_first[$set] )); then set_first[$set]=$i; fi
  done
  for i in "${keep[@]}"; do
    set=${chain[i]}
    printf -v k '%018d %06d %03d %06d' "$((999999999999999999 - set_epoch[$set]))" "${set_first[$set]}" "${step[i]}" "$i"
    keys+=("$k")
  done
  (( ${#keys[@]} )) || return 0
  sorted=$(printf '%s\n' "${keys[@]}" | LC_ALL=C sort)
  while IFS= read -r k; do ORDER+=($((10#${k##* }))); done <<<"$sorted"
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

# mtime FILE: when FILE was last changed, in seconds since the epoch; exit 1
# if it isn't there.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# lock: pending.txt to this run until it exits. A lock older than LOCK_STALE
# is a killed run's (a change takes well under a second).
lock() {
  local tries=0 at now dir=${PENDING%/*}
  [[ $dir != "$PENDING" ]] || dir=.
  mkdir -p "$dir"
  [[ -w $dir ]] || die "can't write in $dir"
  until mkdir "$LOCK" 2>/dev/null; do
    now=$(date +%s)
    at=$(mtime "$LOCK") || at=$now
    if (( now - at >= LOCK_STALE )); then rmdir "$LOCK" 2>/dev/null || true; continue; fi
    tries=$((tries + 1))
    (( tries < 800 )) || die "$LOCK is held; nothing changed"
    sleep 0.05
  done
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

# only I...: J_* cut down to the jobs I.
only() {
  local i
  local -a t=("${J_TYPE[@]}") e=("${J_EPOCH[@]}") w=("${J_WHAT[@]}") b=("${J_BODY[@]}")
  J_TYPE=() J_EPOCH=() J_WHAT=() J_BODY=()
  for i in "$@"; do
    J_TYPE+=("${t[i]}") J_EPOCH+=("${e[i]}") J_WHAT+=("${w[i]}") J_BODY+=("${b[i]}")
  done
}


# move_loose: LOOSE, out of the queue, into ORPHANS, dated, saying so.
move_loose() {
  (( ${#LOOSE[@]} )) || return 0
  mkdir -p "$LOGS"; chmod 700 "$LOGS"
  when
  { printf '# moved out %s\n' "$WHEN"; printf '%s\n' "${LOOSE[@]}"; printf '\n'; } >>"$ORPHANS"
  printf 'pending: moved %d line(s) with no job to %s\n' "${#LOOSE[@]}" "$ORPHANS" >&2
}

# sweep: logs with no job, and orphans.txt, once untouched for KEEP_DAYS.
sweep() {
  local old f i
  local -A wanted=()
  [[ -d $LOGS ]] || return 0
  old=$(find "$LOGS" -maxdepth 1 -type f \( -name '*.log' -o -name orphans.txt \) -mtime +"$KEEP_DAYS" 2>/dev/null) || return 0
  [[ -n $old ]] || return 0
  for i in "${!J_TYPE[@]}"; do wanted[$(log_of "$i")]=1; done
  while IFS= read -r f; do
    [[ -n ${wanted[$f]:-} ]] || rm -f -- "$f"
  done <<<"$old"
}

# save: what has gone taken out, then the queue rendered into a temp file beside
# pending.txt (one name: only the lock's holder writes it), which replaces
# it (only if it differs).
save() {
  local tmp=$PENDING.new mode
  move_loose
  [[ -e $PENDING ]] || : >"$PENDING"
  render >"$tmp" || { rm -f "$tmp"; return 1; }
  sweep || true
  if cmp -s "$tmp" "$PENDING"; then rm -f "$tmp"; return 0; fi
  mode=$(stat -c %a "$PENDING" 2>/dev/null || stat -f %Lp "$PENDING")
  chmod "$mode" "$tmp"
  mv "$tmp" "$PENDING"
}

# one_line NAME VALUE: dies unless VALUE is one non-empty line.
one_line() {
  [[ -n ${2//[$SP]/} ]] || die "$1 can't be empty"
  [[ $2 != *$'\n'* ]] || die "$1 is one line"
}

# body_of LINE...: sets BODY to the job's lines, "# text" notes as "#  text",
# a command without the blanks around it; dies on a bad one.
body_of() {
  local line
  BODY=""
  for line in "$@"; do
    [[ -n ${line//[$SP$'\n']/} && $line != *$'\n'* ]] || die "each LINE is one non-empty line"
    case $line in
      "# "*) line="#  ${line:2}" ;;
      "#"*)  die "a LINE starting # is a note: '# text'" ;;
      *)     line=${line#"${line%%[!"$SP"]*}"} line=${line%"${line##*[!"$SP"]}"} ;;
    esac
    BODY+=${BODY:+$'\n'}$line
  done
}


# message_of LINE...: sets BODY to a message's text: the LINEs as given
# (stdin's text with none), without blank lines at either end; dies on an
# empty one, or one holding a line pending.txt would read as a job's head or
# the line.
message_of() {
  local text i first=-1 last=-1 line
  local -a l=()
  if (( $# )); then text=$(printf '%s\n' "$@"); else text=$(cat); fi
  while IFS= read -r line; do l+=("$line"); done <<<"$text"
  for i in "${!l[@]}"; do
    [[ -n ${l[i]//[$SP]/} ]] || continue
    if (( first < 0 )); then first=$i; fi
    last=$i
  done
  (( first >= 0 )) || die "a message can't be empty"
  BODY=""
  for (( i = first; i <= last; i++ )); do
    [[ ${l[i]} != "$SEP" && ! ${l[i]} =~ $HEAD_RE ]] || die "a message's line would end it in pending.txt: ${l[i]}"
    BODY+=${l[i]}
    if (( i < last )); then BODY+=$'\n'; fi
  done
}

# fits TYPE EPOCH WHAT BODY: dies unless a job above the line is WIDTH wide
# at most: its head line and every note of BODY (a command, and a message's
# own lines, are as long as they are).
fits() {
  local head line
  [[ $1 != "$HAND" ]] || return 0
  head="# $2 $1: $3"
  (( ${#head} <= WIDTH )) || die "the head line is ${#head} characters, over $WIDTH: shorten WHAT"
  [[ $1 != "$MESSAGE" ]] || return 0
  while IFS= read -r line; do
    [[ $line == "#"* ]] || continue
    (( ${#line} <= WIDTH )) || die "a note is ${#line} characters as written, over $WIDTH: $line"
  done <<<"$4"
}

# a_chain_named WHAT: dies if WHAT is a step whose chain has no NAME.
a_chain_named() {
  step_of "$1" || return 0
  [[ -n ${S_NAME//[ (\[]/} ]] ||
    die "a chain's WHAT starts with its NAME, the same in every step ('root tools 1/2: read the diff'): $1"
}

cmd_add() {
  [[ $# -ge 2 ]] || die "usage: pending.sh add TYPE WHAT LINE..."
  local type=$1 what=$2 i found=0 line stype epoch
  shift 2
  one_line TYPE "$type"; one_line WHAT "$what"
  [[ $type =~ $TYPE_RE ]] || die "a TYPE is single-spaced words, none of them only digits or with a colon"
  epoch=$((10#$NOW))
  words "$what"; what=$WORDS
  a_chain_named "$what"
  short "$type"; stype=$SHORT
  if [[ $stype == "$MESSAGE" ]]; then message_of "$@"
  else
    (( $# )) || die "usage: pending.sh add TYPE WHAT LINE..."
    body_of "$@"
  fi
  local body=$BODY
  fits "$stype" "$epoch" "$what" "$body"
  lock
  load
  job "$type" "$what" "$body"
  local n_type=$N_TYPE n_what=$N_WHAT n_body=$N_BODY
  for i in "${!J_TYPE[@]}"; do
    unmarked "${J_BODY[i]}"
    if [[ ${J_TYPE[i]} == "$n_type" && ${J_WHAT[i]} == "$n_what" && $UNMARKED == "$n_body" ]]; then
      found=1
      J_BODY[i]=$UNMARKED
      if [[ $n_type != "$HAND" ]] && (( epoch < J_EPOCH[i] )); then J_EPOCH[i]=$epoch; fi
    fi
  done
  if (( ! found )); then
    # First in the file, so it is first among jobs of the same second.
    J_TYPE=("$n_type" "${J_TYPE[@]}") J_EPOCH=("$epoch" "${J_EPOCH[@]}")
    J_WHAT=("$n_what" "${J_WHAT[@]}") J_BODY=("$n_body" "${J_BODY[@]}")
  fi
  save
}

# says PREFIX WHAT I: exit 0 if job I says WHAT (or starts with it, when
# PREFIX is 1); a by-hand job's paragraph says WHAT when it is WHAT or runs
# on from it.
says() {
  local text=${J_WHAT[$3]}
  if (( $1 )); then [[ $text == "$2"* ]]; return; fi
  words "$2"
  if [[ ${J_TYPE[$3]} == "$HAND" ]]; then
    after "$WORDS"
    [[ $text == "$WORDS" || $text == "$WORDS$AFTER"* ]]
  else
    [[ $text == "$WORDS" ]]
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
  local t
  t=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  t=${t:0:48}
  printf '%s' "${t%-}"
}

# log_of I: job I's log file.
log_of() { printf '%s/%s-%s.log' "$LOGS" "${J_EPOCH[$1]}" "$(slug "${J_WHAT[$1]}")"; }

cmd_remove() {
  local i log
  local -a kept=()
  what_args remove "$@"
  [[ -f $PENDING ]] || return 0
  lock
  load
  for i in "${!J_TYPE[@]}"; do
    if says "$PREFIX" "$WHAT" "$i"; then
      log=$(log_of "$i")
      rm -f -- "$log"
    else
      kept+=("$i")
    fi
  done
  only "${kept[@]}"
  save
}

cmd_has() {
  local i
  what_args has "$@"
  [[ -f $PENDING ]] || return 1
  load
  for i in "${!J_TYPE[@]}"; do
    if says "$PREFIX" "$WHAT" "$i"; then return 0; fi
  done
  return 1
}

# wanted I WHAT...: exit 0 if job I says one of the WHATs, or none is given.
wanted() {
  local i=$1 w
  shift
  (( $# )) || return 0
  for w in "$@"; do
    if says 0 "$w" "$i"; then return 0; fi
  done
  return 1
}

# show [WHAT...]: the head lines in ORDER, every job's or only those saying
# one of the WHATs, then the line and the by-hand prose as the file has it;
# nothing for a missing pending.txt.
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

# log_says LOG: sets LOG_SAYS to the mark LOG ends with, without its "#  ".
log_says() {
  local last="" l
  while IFS= read -r l || [[ -n $l ]]; do last=$l; done <"$1"
  LOG_SAYS=""
  if [[ $last =~ $MARK_RE ]]; then LOG_SAYS=${last#\#  }; fi
}

# result WHAT: how the job stands, from the file or, when it has left it, from
# the newest log headed WHAT.
cmd_result() {
  [[ $# -eq 1 && -n $1 ]] || die "usage: pending.sh result WHAT"
  local i log first f best=-1 at name
  load
  for i in "${!J_TYPE[@]}"; do
    says 0 "$1" "$i" || continue
    first=${J_BODY[i]%%$'\n'*}
    if [[ $first =~ $MARK_RE ]]; then printf '%s\n' "${first#\#  }"; else printf 'waiting\n'; fi
    log=$(log_of "$i")
    if [[ -f $log ]]; then printf 'log: %s\n' "$log"; fi
    return 0
  done
  words "$1"
  log="" name=$(slug "$WORDS")
  for f in "$LOGS"/*-"$name".log; do
    [[ -f $f ]] || continue
    IFS= read -r first <"$f" || continue
    [[ $first == "# $WORDS" ]] || continue
    at=${f##*/} at=${at%%-*}
    [[ $at =~ ^[0-9]{1,18}$ ]] || continue
    if (( 10#$at > best )); then best=$((10#$at)) log=$f; fi
  done
  [[ -n $log ]] || return 1
  log_says "$log"
  printf 'gone from pending.txt, %s\n' "${LOG_SAYS:-no result in its log}"
  printf 'log: %s\n' "$log"
}

# status: what the file holds, what needs looking at, what is kept beside it.
cmd_status() {
  local i waiting=0 oks=0 fails=0 byhand=0 first days logs=0 strays=0 f
  local -a old=() failed=()
  local -A wanted_log=()
  load
  ordered
  for i in "${ORDER[@]}"; do
    if [[ ${J_TYPE[i]} == "$HAND" ]]; then byhand=$((byhand + 1)); continue; fi
    wanted_log[$(log_of "$i")]=1
    first=${J_BODY[i]%%$'\n'*}
    if [[ $first =~ $OK_RE ]]; then oks=$((oks + 1))
    elif [[ $first =~ $MARK_RE ]]; then fails=$((fails + 1)); failed+=("$i")
    else
      waiting=$((waiting + 1))
      days=$(( (NOW - J_EPOCH[i]) / 86400 ))
      if (( days > STALE_DAYS )); then old+=("$days days: ${J_WHAT[i]}"); fi
    fi
  done
  printf '%s: %d waiting, %d ran ok, %d failed, %d by hand\n' "$PENDING" "$waiting" "$oks" "$fails" "$byhand"
  for i in "${failed[@]}"; do
    printf '[ !! ] failed: %s (%s)\n' "${J_WHAT[i]}" "${J_BODY[i]%%$'\n'*}"
  done
  for i in "${old[@]}"; do printf '[ !! ] waiting %s\n' "$i"; done
  if (( ${#LOOSE[@]} )); then printf '[ !! ] %d line(s) with no job: the next change moves them out\n' "${#LOOSE[@]}"; fi
  [[ ! -d $LOCK ]] || printf '[ !! ] %s is held\n' "$LOCK"
  for f in "$LOGS"/*.log; do
    [[ -f $f ]] || continue
    logs=$((logs + 1))
    [[ -n ${wanted_log[$f]:-} ]] || strays=$((strays + 1))
  done
  printf 'logs: %d, %d with no job in the file (kept %d days)\n' "$logs" "$strays" "$KEEP_DAYS"
  if [[ -f $ORPHANS ]]; then printf 'orphans: %s (kept %d days)\n' "$ORPHANS" "$KEEP_DAYS"; fi
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

# when: sets WHEN to NOW as the ran note writes it: "Thu 8 Oct, 9:14pm" (BSD
# date has no %P, so its AM or PM is lowered here).
when() {
  local t
  if (( GNU_DATE )); then WHEN=$(LC_ALL=C date -d "@$NOW" '+%a %-d %b, %-I:%M%P'); return; fi
  t=$(LC_ALL=C date -r "$NOW" '+%a %-d %b, %-I:%M%p')
  t=${t/%AM/am}
  WHEN=${t/%PM/pm}
}

# mark_of EXIT: sets MARK to the mark for that exit.
mark_of() {
  when
  if (( 10#$1 == 0 )); then MARK="#  ran $WHEN: ok"
  else MARK="#  ran $WHEN: failed (exit $((10#$1)))"; fi
}

# mark WHAT EXIT [LINE]: reads the file and marks the jobs saying WHAT (only
# one running LINE, if named), replacing their last mark; exit 1 if none.
mark() {
  local i found=0
  mark_of "$2"
  load
  for i in "${!J_TYPE[@]}"; do
    [[ ${J_TYPE[i]} != "$HAND" && ${J_TYPE[i]} != "$MESSAGE" && ${J_WHAT[i]} == "$1" ]] || continue
    if (( $# > 2 )) && ! runs "$i" "$3"; then continue; fi
    found=1
    unmarked "${J_BODY[i]}"
    J_BODY[i]=$MARK${UNMARKED:+$'\n'$UNMARKED}
  done
  (( found ))
}

cmd_ran() {
  [[ $# -eq 2 && -n $1 ]] || die "usage: pending.sh ran WHAT EXIT"
  [[ $2 =~ ^[0-9]{1,9}$ ]] || die "EXIT is a number"
  lock
  mark "$1" "$2" || die "no job says: $1"
  save
}

# cmd_run LINE: nothing it can fail at stops the user's command: it says
# NOT_A_JOB, and the shell runs the line itself.
cmd_run() {
  [[ $# -eq 1 && -n $1 ]] || die "usage: pending.sh run LINE"
  local log what
  find_line "$1" || return "$NOT_A_JOB"
  what=${J_WHAT[FOUND]} log=$(log_of "$FOUND")
  { mkdir -p "$LOGS" && chmod 700 "$LOGS" && printf '# %s\n' "$what" >"$log"; } 2>/dev/null || return "$NOT_A_JOB"
  # The caller's locale, not this script's.
  if [[ -n $CALLER_HAD_LC_ALL ]]; then export LC_ALL=$CALLER_LC_ALL; else unset LC_ALL; fi
  exec "$BASH" -c "$RUNNER" pending "$1" "$log" "$what" "$BASH" "${BASH_SOURCE[0]}"
}

# ended LOG WHAT LINE EXIT: the mark, in the log and on the job that ran; a job
# gone from the file meanwhile, or a file it can't change, changes nothing
# about how the run ends.
cmd_ended() {
  [[ $# -eq 4 && $4 =~ ^[0-9]{1,9}$ ]] || die "usage: pending.sh ended LOG WHAT LINE EXIT"
  local log=$1 what=$2 line=$3 rc=$((10#$4))
  mark_of "$rc"
  { printf '%s\n' "$MARK" >>"$log"; } 2>/dev/null || true
  set +e
  (
    set -e
    lock
    if mark "$what" "$rc" "$line"; then save; fi
  )
  set -e
  # A failure is easy to see at a glance; the terminal only, not the log.
  (( rc == 0 )) || printf 'ERROR: %s failed (exit %d)\n' "$what" "$rc" >&2
  if (( rc == NOT_A_JOB )); then return 1; fi
  return "$rc"
}

main() {
  local cmd=${1:-}; shift || true
  [[ $NOW =~ ^[0-9]{1,18}$ ]] || die "NOW is seconds since the epoch"
  case $cmd in
    add)     cmd_add "$@" ;;
    remove)  cmd_remove "$@" ;;
    has)     cmd_has "$@" ;;
    tidy)    [[ -f $PENDING ]] || return 0; lock; load; save ;;
    show)    cmd_show "$@" ;;
    result)  cmd_result "$@" ;;
    status)  cmd_status "$@" ;;
    version) printf 'pending %s\n' "$VERSION" ;;
    match)   cmd_match "$@" ;;
    ran)     cmd_ran "$@" ;;
    run)     cmd_run "$@" ;;
    ended)   cmd_ended "$@" ;;
    *) die "usage: pending.sh add|remove|has|tidy|show|result|status|version|match|ran|run|ended (see the top of this file)" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
