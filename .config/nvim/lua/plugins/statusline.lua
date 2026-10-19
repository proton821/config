-- The right end of LazyVim's statusline, trimmed: no plugin-update count
-- (the plugins stay at lazy-lock.json's commits) and no clock. How far
-- through the file and the cursor's line:column stay.
return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    local updates = require("lazy.status").updates
    opts.sections.lualine_x = vim.tbl_filter(function(component)
      return not (type(component) == "table" and component[1] == updates)
    end, opts.sections.lualine_x)
    opts.sections.lualine_z = {}
  end,
}
