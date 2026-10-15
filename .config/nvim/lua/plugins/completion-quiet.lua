-- No completion menu while typing and no ghost text to the right of the
-- cursor. Ctrl+Space still opens the menu when I ask for it. Matching runs
-- in Lua, so no prebuilt binary is downloaded from GitHub and run.
return {
  "saghen/blink.cmp",
  opts = {
    completion = {
      menu = { auto_show = false },
      ghost_text = { enabled = false },
    },
    fuzzy = { implementation = "lua" },
  },
}
