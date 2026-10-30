-- Options are automatically loaded before lazy.nvim startup.
-- The OSC 52 clipboard for SSH and tmux sessions. The Mac's Neovim
-- reaches its clipboard itself (pbcopy), and its copy has no such file.
if vim.fn.has("mac") == 0 then
  require("config.remote_clipboard").setup()
end

vim.opt.relativenumber = true
vim.g.autoformat = false

-- No swap files, so a Neovim that didn't exit cleanly leaves no
-- "swap file exists" warning for the next one.
vim.opt.swapfile = false
vim.opt.undofile = true

-- Neovide: JetBrainsMono Nerd Font at Ghostty's font-size; the rig's
-- display/sizes.sh sets both. The Mac sets its own font and size.
if vim.g.neovide then
  if vim.fn.has("mac") == 0 then
    vim.o.guifont = "JetBrainsMono Nerd Font:h18.75"
  end
  -- Dark on every system. Neovide follows the system's appearance, and a
  -- light one would paint white behind the theme's text, since
  -- plugin/after/transparency.lua clears the theme's background.
  vim.g.neovide_theme = "dark"
  vim.o.background = "dark"
  -- The cursor jumps straight to its new place: no sliding trail between
  -- lines, no particle effects.
  vim.g.neovide_cursor_animation_length = 0
  vim.g.neovide_cursor_short_animation_length = 0
  vim.g.neovide_cursor_trail_size = 0
  vim.g.neovide_cursor_animate_command_line = false
  vim.g.neovide_cursor_vfx_mode = ""
end

-- No tab-page line either (bufferline is off in plugins/no-tabs.lua).
vim.o.showtabline = 0
