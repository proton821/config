-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- No spell check: LazyVim turns it on (with wrap) for text, Markdown and git
-- commits. Keep the wrap, drop the spelling.
vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("wrap_no_spell", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
  end,
})

-- Close the Neo-tree file tree before a session is saved (persistence saves
-- one per folder on quit, from any Neovim), or it comes back as an empty pane.
vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("neo_tree_session", { clear = true }),
  pattern = "PersistenceSavePre",
  callback = function()
    if package.loaded["neo-tree"] then
      vim.cmd("Neotree close")
    end
  end,
})

-- Neovide: reopen the files from the last session in this folder when started
-- without files, then show the Neo-tree file tree on the left without taking
-- focus. The tree is skipped when started on a directory (Neo-tree already
-- opens there). LazyVim loads this file on VeryLazy, after startup, when
-- Neovim starts without files, and during startup when it starts with them.
if vim.g.neovide then
  -- Scheduled so it runs after the VeryLazy autocmd returns: loading a session
  -- inside an autocmd skips the nested FileType events, leaving no highlighting.
  vim.schedule(function()
    if vim.fn.argc() == 0 then
      require("persistence").load()
    end

    local arg = vim.fn.argv(0)
    local stat = arg ~= "" and vim.uv.fs_stat(arg) or nil
    if not (stat and stat.type == "directory") then
      require("neo-tree.command").execute({ action = "show", dir = vim.uv.cwd() })
    end
  end)
end

-- One file at a time, no tabs: a file opened from Neo-tree (or a picker)
-- replaces the one in focus, and the buffer it replaced is closed rather than
-- kept hidden, so there is nothing to cycle through. A buffer with unsaved
-- changes is kept until it is saved; one still shown in a split, in any tab
-- page, stays open. Closed is :bdelete, not a wipe, so the alternate file
-- (#) and quickfix lists still reach it.
vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("one_file", { clear = true }),
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then
      return
    end
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
          buf ~= ev.buf
          and vim.bo[buf].buflisted
          and vim.bo[buf].buftype == ""
          and not vim.bo[buf].modified
          and #vim.fn.win_findbuf(buf) == 0
        then
          pcall(vim.cmd.bdelete, buf)
        end
      end
    end)
  end,
})
