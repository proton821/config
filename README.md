# config

The look and feel of one machine, published for another (a Mac) to take:
Neovim (LazyVim, with Neovide's settings), herdr, one colour theme for
Neovim, Ghostty and Claude Code (herdr follows Ghostty's colours), and the
rules for Claude Code that hold on both machines (`claude-rules.md`).

It goes one way. Changes are made at the source and arrive here; nothing
is edited in this repo, and `install.sh update` discards any change made in
a clone of it (edited or added files, commits), listing each first.

## On the Mac

    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c credential.helper= clone https://github.com/proton821/config.git ~/.local/share/config
    bash ~/.local/share/config/install.sh

and, for the latest:

    bash ~/.local/share/config/install.sh update

The clone and `update`'s fetch offer no credential and leave the Mac's own
git config out, so nothing in it can send them elsewhere. `update` lists the
commits and files it takes (`git log --stat`) before it resets to them.

`install.sh status` shows what is in place. It links `~/.config/nvim`,
`~/.config/herdr/config.toml`, the Ghostty theme
`~/.config/ghostty/themes/omarchy` and the Claude Code theme
`~/.claude/themes/omarchy.json` to this repo (under `$XDG_CONFIG_HOME`
where that is set). Anything already there is moved aside to
`NAME.before-config` (`.2` and on, if that is taken), and with an earlier
Neovim config go its plugins (`~/.local/share/nvim/lazy`). It puts one line
in `~/.config/ghostty/config.ghostty` including `.config/ghostty/mac` (the
theme, the left Option key as Alt, and Alt+Left and Alt+Right left to
herdr), Claude Code's `theme` in `~/.claude/settings.json`, and one line
importing `claude-rules.md` in `~/.claude/CLAUDE.md`, leaving the rest of
each file alone; `status` reports any Ghostty config whose colours, or
included theme, win over it.

Needs git, jq (macOS 15 has it), Neovide, Ghostty, herdr and
JetBrainsMono Nerd Font; and for Neovim, Neovim 0.12 or later, ripgrep
(its searches) and the tree-sitter CLI (Homebrew's `tree-sitter-cli`) with
a C compiler (Xcode's Command Line Tools) to build its parsers. `install.sh
status` says which of `nvim`, `tree-sitter` and `rg` PATH lacks.

Neovim's first start installs lazy.nvim and its plugins, each at the
commit `lazy-lock.json` pins, then nvim-treesitter's parsers, each fetched
from GitHub as source and built here. It downloads no binaries and doesn't
check for plugin updates. When an update brings new pins, `install.sh`
lists the plugins not at them, and `:Lazy restore` in Neovim fetches them.
For language support, install `lua-language-server`, `shfmt` and `stylua`
with Homebrew (Neovim finds them on PATH).
