-- LazyVim declares tokyonight and catppuccin itself, and Omarchy's theme packs
-- (all-themes.lua) use them; this config has the one theme (blackgold, on
-- aether), so they would be cloned and never used. Off on every system.
return {
  { "folke/tokyonight.nvim", enabled = false },
  { "catppuccin/nvim", name = "catppuccin", enabled = false },
}
