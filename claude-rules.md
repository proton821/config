# Shared rules

The parts of another machine's Claude Code instructions that hold here
too. Published one way: they are changed at the source, not here.

## How I work

- These are my defaults for my own files and replies; where a
  repository, team or employer has its own conventions or
  instructions, theirs win.
- I value **verifiable, open-source** tools. Lead with what can be
  inspected; say where the openness stops.
- Decisions and accepted risks go in documents beside the work they are
  about, not the chat.
- **Documents say what is true now**, not how it got there: no dated logs,
  no timestamps in prose, a reason only where needed. A change rewrites
  the text it contradicts. **One version per document**, no `-vN` in its
  name; a plan is redrafted whole in place. Cite the canonical document
  instead of duplicating it; a repeat collapses to a pointer. (Dates stay
  in data, such as reminders and dated file names.)
- Say which claims are verified and which are assumed.
- Read my screenshots as evidence; don't ask me to retype them.
- **Scripts first:** procedures become scripts, not English steps. Every
  `foo.sh` has a sibling `foo.bats` that runs without root, hardware or
  network. **After changing a script, run only the relevant tests**: its
  `.bats`, the `.bats` of scripts that call or source it, and
  `shellcheck -x` on the changed `.sh` and `.bats` (`bats-core` and
  `shellcheck` from Homebrew on the Mac).
- **ShellCheck-clean:** `shellcheck -x` shows nothing on every `.sh` and
  `.bats`; every `disable=` gives its reason. No `eval`.

## Language and times

- **British English** everywhere I read. **Dates:** where they sort (file
  and folder names, data, headings), `2026-09-24`, `2026-09-24T13:53`;
  elsewhere, in prose and script output, `Wed 24 Sep 2026`. Quotes,
  commands and identifiers stay as they are.
- **Take every time from `date`** (or a screenshot's clock); never estimate.
- **Times as `1:53pm`**: 12-hour, lowercase am/pm, no space, converted log
  times included; quoted logs stay as they are. In scripts with GNU
  date: `LC_TIME=C date '+%-I:%M%P'`; BSD date (macOS) has no `%P`:
  `LC_TIME=C date '+%-I:%M%p' | tr '[:upper:]' '[:lower:]'`.

## Commands I run myself

**Anything that prompts can't run from a tool call:** logins,
passphrases, confirmations. Assume I can't type a password unless I say
so. Don't run or wait on these: put them in pending.txt.

**`~/x/pending.txt` is changed only with `bash ~/x/vendor/config/bin/pending.sh`** (`add
TYPE WHAT LINE...`, `remove [--prefix] WHAT`, `has`, `tidy`, `show
[WHAT...]`; its header is the layout spec). A job is known by its WHAT.

- Only a command I can run **right now**; later steps stay in the work's
  own README.
- **TYPE is exactly what I do, shortest form**: "run" (a command),
  "block" (a command your sandbox blocked), "hand" (a step in an app,
  lines as `# ` notes, written as prose below the line), "message" (a
  Slack message, a Jira or PR comment to post: WHAT says where; the text
  whole, any lines, any length, so I yank it in one go). **Every command
  I type is a job above the line**, so my run of it is noted. No "(...)"
  in a type; reuse existing types exactly. **72 wide** (`pending.sh`
  refuses longer): head line and notes; a command or a message is as long
  as it is.
- Exact, runnable commands, no placeholders; number a multi-step WHAT
  (1/3, 2/3, 3/3). More than a couple of steps becomes a **resumable**
  script, run in one line.
- Remove another session's job only when verified done; put back one of
  yours that's gone but not done.
- When I say a job is done, verify read-only, then remove it. A job I ran
  gets a first note `#  ran ...: ok` or `failed (exit N)` (the shell's
  hook), output in `~/.local/state/pending/`: check both at session start
  and when its topic comes up.
- Put the blocked step in pending.txt, finish the rest, say what's left.
- **Never put a command in the reply**, nor prefix one with `!`. End with
  "Waiting in `~/x/pending.txt`:" and a code block of the head lines of the jobs **tied to that reply's topic**,
  exactly as `pending.sh show WHAT...` prints them; no other session's or
  topic's.
