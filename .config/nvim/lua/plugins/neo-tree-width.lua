-- Remember the Neo-tree width across launches: saved whenever the tree's side
-- window is resized (not a floating one), read back when Neo-tree loads.
local file = vim.fn.stdpath("state") .. "/neo-tree-width"

return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    local ok, lines = pcall(vim.fn.readfile, file)
    local width = ok and tonumber(lines[1])
    if width then
      opts.window = opts.window or {}
      opts.window.width = width
    end

    vim.api.nvim_create_autocmd("WinResized", {
      group = vim.api.nvim_create_augroup("neo_tree_width", { clear = true }),
      callback = function()
        for _, win in ipairs(vim.v.event.windows) do
          if
            vim.api.nvim_win_is_valid(win)
            and vim.api.nvim_win_get_config(win).relative == ""
            and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree"
          then
            vim.fn.writefile({ tostring(vim.api.nvim_win_get_width(win)) }, file)
          end
        end
      end,
    })
  end,
}
