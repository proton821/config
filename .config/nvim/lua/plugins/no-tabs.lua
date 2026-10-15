-- No tab bar: the file shown is chosen from Neo-tree on the left (or the
-- pickers) and replaces the one in focus (config/autocmds.lua, "one_file").
-- bufferline.nvim is off altogether, so it isn't installed.
return {
  { "akinsho/bufferline.nvim", enabled = false },
}
