-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Neovide on the Mac: Cmd+S saves, Cmd+C copies and Cmd+V pastes, as in its
-- other apps (Neovide passes keys on and maps none of its own).
if vim.g.neovide and vim.fn.has("mac") == 1 then
  vim.keymap.set({ "i", "x", "n", "s" }, "<D-s>", "<cmd>w<cr><esc>", { desc = "Save File" })
  vim.keymap.set("x", "<D-c>", '"+y', { desc = "Copy" })
  vim.keymap.set({ "n", "x" }, "<D-v>", '"+P', { desc = "Paste" })
  vim.keymap.set("i", "<D-v>", "<C-r><C-o>+", { desc = "Paste" })
  vim.keymap.set("c", "<D-v>", "<C-r><C-r>+", { desc = "Paste" })
end
