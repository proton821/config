-- No Mason: nothing in Neovim downloads binaries. Language servers and
-- formatters (lua-language-server, shfmt, stylua) come from the system's
-- package manager and are found on PATH; LazyVim sets them up without it.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}
