# Shared rules

The parts of another machine's Claude Code instructions that hold here
too. Published one way: they are changed at the source, not here.

## How I work

- These are my defaults for my own files and replies; where a
  repository, team or employer has its own conventions or
  instructions, theirs win.
- Lay out the trade-off, then give **a clear recommendation**, not a survey.
- I value **verifiable, open-source** tools. Lead with what can be
  inspected; say where the openness stops.
- Decisions and accepted risks go in documents beside the work they are
  about, not the chat.
- **Documents say what is true now**, not how it got there: no dated logs,
  no timestamps in prose, a reason only where needed. A change rewrites
  the text it contradicts. **One version per document**, no `-vN` in its
  name; a plan is redrafted whole in place. (Dates stay in data, such as
  reminders and dated file names.)
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
