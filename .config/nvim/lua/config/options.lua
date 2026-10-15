-- Options are automatically loaded before lazy.nvim startup.
-- The OSC 52 clipboard for SSH, tmux and herdr sessions. The Mac's Neovim
-- reaches its clipboard itself (pbcopy), and its copy has no such file.
if vim.fn.has("mac") == 0 then
  require("config.remote_clipboard").setup()
end

vim.opt.relativenumber = false
vim.g.autoformat = false

-- Neovide: Omarchy's monospace font (fontconfig, as `omarchy font current`
-- reads it, so `omarchy font set` carries over) at the terminals' size 18;
-- on the Mac, JetBrainsMono Nerd Font.
if vim.g.neovide then
  local font
  if vim.fn.has("mac") == 0 and vim.fn.executable("fc-match") == 1 then
    local found = vim.system({ "fc-match", "monospace", "-f", "%{family}" }, { text = true }):wait()
    font = found.code == 0 and found.stdout:match("^[^,\n]+") or nil
  end
  vim.o.guifont = (font or "JetBrainsMono Nerd Font") .. ":h18"
  -- Dark on every system. Neovide follows the system's appearance, and a
  -- light one would paint white behind the theme's text, since
  -- plugin/after/transparency.lua clears the theme's background.
  vim.g.neovide_theme = "dark"
  vim.o.background = "dark"
  -- The Mac: the left Option key is Alt, for LazyVim's Alt keys; the right
  -- one still types # and € on a British layout.
  vim.g.neovide_input_macos_option_key_is_meta = "only_left"
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
