-- LazyVim declares tokyonight and catppuccin itself. Omarchy's theme packs
-- use them on Linux; the Mac has the one theme, so there they'd be cloned and
-- never used.
local mac = vim.fn.has("mac") == 1

return {
  { "folke/tokyonight.nvim", enabled = not mac },
  { "catppuccin/nvim", name = "catppuccin", enabled = not mac },
}
