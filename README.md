# config

What one machine shares with another (a Mac), published for it to take:
Neovim (LazyVim, with Neovide's settings), Ghostty's settings, one colour
theme for Neovim, Ghostty and Claude Code, Claude Code's settings, and the
rules for Claude Code that hold on both machines (`claude-rules.md`), and
`bin/pending.sh`, the one way `~/x/pending.txt` is changed: what is left
for me to run or do by hand (its header is the layout; bash 5,
Homebrew's: `bash bin/pending.sh`; tests: `bats bin/pending.bats`), with
its zsh hook (tests: `bats bin/pending-hook.bats`): a command from
pending.txt run exactly as written goes through `pending.sh run`, so its
job is marked `ran ...: ok` or `failed (exit N)` as it ends, its
output is kept in `~/.local/state/pending/`, and a failure ends with
`ERROR: ...`. Every other line runs untouched. `bin/keys.sh` prints the
cheat sheet of the keys used on both machines (tests: `bats bin/keys.bats`).

It goes one way. Changes are made at the source and arrive here; nothing
is edited in this repo, and `install.sh update` discards any change made in
a clone of it (edited or added files, commits), listing each first.

## On the Mac

    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c credential.helper= clone https://github.com/proton821/config.git ~/x/vendor/config
    bash ~/x/vendor/config/install.sh

and, for the latest:

    bash ~/x/vendor/config/install.sh update

The clone and `update`'s fetch offer no credential and leave the Mac's own
git config out, so nothing in it can send them elsewhere. `update` lists the
commits and files it takes (`git log --stat`) before it resets to them.

`install.sh status` shows what is in place. It links `~/.config/nvim`,
the Ghostty theme
`~/.config/ghostty/themes/blackgold` and the Claude Code theme
`~/.claude/themes/blackgold.json` and ShellCheck's settings
`~/.config/shellcheckrc` to this repo (under `$XDG_CONFIG_HOME`
where that is set). Anything already there is moved aside to
`NAME.before-config` (`.2` and on, if that is taken), and with an earlier
Neovim config go its plugins (`~/.local/share/nvim/lazy`). A link an
earlier release made to a file the repo no longer ships (herdr's
`~/.config/herdr/config.toml`, and the themes by their earlier name,
`omarchy`) is removed. It puts one line
in `~/.config/ghostty/config.ghostty` including `.config/ghostty/mac` (the
settings shared with the other machine, Shift+Enter as a new line in
Claude Code among them, then the theme); one line at the end of
`~/.zshrc` (in `$ZDOTDIR`, if that is set) loading pending.txt's hook, which
does nothing once the clone has gone; the keys of `claude-settings.json` (the theme,
vim editing, auto-memory off and the rest) in `~/.claude/settings.json`, and one line importing `claude-rules.md` in
`~/x/CLAUDE.md`, leaving the rest of each file alone; `status` reports any
Ghostty config whose colours, or included theme, win over it.

Only what both machines share is here. The Mac's own settings (font
sizes, notifications, how its apps start) are its own, set on it.

Needs git, jq (macOS 15 has it), Neovide, Ghostty, JetBrainsMono Nerd Font, and Homebrew's bash first on PATH for pending.sh;
and for Neovim, Neovim 0.12 or later, ripgrep (its searches) and the tree-sitter CLI (Homebrew's `tree-sitter-cli`) with
a C compiler (Xcode's Command Line Tools) to build its parsers. `install.sh
status` says which of `nvim`, `tree-sitter` and `rg` PATH lacks.

Neovim's first start installs lazy.nvim and its plugins, each at the
commit `lazy-lock.json` pins, then nvim-treesitter's parsers, each fetched
from GitHub as source and built here. It downloads no binaries and doesn't
check for plugin updates. When an update brings new pins, `install.sh`
lists the plugins not at them, and `:Lazy restore` in Neovim fetches them.
For language support, install `lua-language-server`, `shfmt` and `stylua`
with Homebrew (Neovim finds them on PATH).
