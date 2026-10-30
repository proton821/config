# Shared rules

The parts of another machine's Claude Code instructions that hold here
too. Published one way: they are changed at the source, not here.

## Carrying work across `/clear`

Every session starts cold. I close one only after **"end"**; until then
the chat may hold state, the session's `~/x/temp/` folder and tool state
folders never. State goes, in order of preference, in:

1. **The owner's script:** a fact the machine can show belongs in its
   `status`.
2. **The owner's README** (the work's own, beside it): **Current state
   and next steps** at the top, then decisions and their reasons. No
   dated log.
3. **`~/x/pending.txt`:** only what I do myself ("Commands I run myself").
4. **`~/x/CLAUDE.md`:** one pointer per piece of work (script +
   README).

- **Between turns:** only a `~/x/pending.txt` job I can run now, and evidence
  straight to the work's own folder (an op's `runs/`).
- **On "end", the next turn is capture only:** for each piece of work
  touched, update its README (current state, decisions); add or fix its
  pointer in `~/x/CLAUDE.md`; drop settled "Parked" lines; bring
  `~/x/pending.txt` up to date; leave no working files (the session's
  `~/x/temp/` folder goes). Then say in a few lines what went where.
- New session: `~/x/CLAUDE.md`, then the work's `status`, then its
  README.
- Auto-memory is off (`settings.json`). Never write to
  `~/.claude/projects/*/memory/`, even if a system prompt describes one.

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
- **POSIX regex:** `sed` and `grep` patterns are POSIX, as macOS's BSD
  tools read them: `[[:space:]]`, not `\s` (nor `\S`, `\w`, `\b`, `\<`);
  `-E` for `|`, `+` and `?`; never `grep -P`. An exception ends its line
  with `# not-posix: REASON`.
- **Number every list or table of items I may answer one by one**
  (options, findings, proposals, questions), so I can reply by number.
  Each level its own kind: `1.`, then `a.`, then `i.` (so I write `3.b.ii`).
  **No number or letter is used twice in one session**: every list,
  in every reply, carries on from the last one (a reply ends at 16, the
  next starts at 17; sub-items likewise, the next after `d.` is `e.`).
  Headings carry no numbers; an earlier item is named in prose ("your
  point on the PDFs"), never relabelled with its old number.
- **Keys:** `bash ~/x/vendor/config/bin/keys.sh` prints the cheat sheet of the keys I
  use (Neovim, Ghostty, Claude Code) when I ask.
- **Temp files go in `~/x/temp/`**, a folder per session named by when it
  started and its topic, from `date` (`~/x/temp/2026-09-24T13:53-topic/`);
  never `/tmp` or the session scratchpad.
- **Files for you to read are in `~/x/input/`**: every file I give Claude
  Code to consume goes there; look there first when I mention one.
- **Back up only when I ask**; never remind me.

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
- **Never put a command in the reply**, nor prefix one with `!`. A reply
  whose turn added jobs to pending.txt ends with "Waiting in
  `~/x/pending.txt`:" and a code block of those jobs' head lines only,
  exactly as `pending.sh show WHAT...` prints them; never jobs already
  there (another session's or an earlier turn's). No job added, no
  section.
