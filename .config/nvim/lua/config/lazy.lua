local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  -- lazy.nvim installs only what is missing, so its own pin in
  -- lazy-lock.json is checked out here.
  if vim.v.shell_error == 0 then
    local read, lock = pcall(function()
      local file = vim.fn.stdpath("config") .. "/lazy-lock.json"
      return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))["lazy.nvim"]
    end)
    if read and lock and lock.commit then
      out = vim.fn.system({ "git", "-C", lazypath, "checkout", "-q", lock.commit })
    end
  end
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(lazypath, "rf")
    vim.api.nvim_echo({
      { "Failed to install lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- Not on the Mac: its plugins stay at the commits lazy-lock.json pins, so
  -- fetching every plugin's repo each hour would buy nothing there.
  checker = {
    enabled = vim.fn.has("mac") == 0, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
