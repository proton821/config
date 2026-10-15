return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#000000",
        dark_bg = "#000000",
        darker_bg = "#000000",
        lighter_bg = "#1f1a12",

        fg = "#ebdbb2",
        dark_fg = "#dcd3b1",
        light_fg = "#ebdbb2",
        bright_fg = "#F6F1DD",
        muted = "#807c6d",

        red = "#D35F5F",
        yellow = "#4D574E",
        orange = "#d86a29",
        green = "#a3850e",
        cyan = "#7A6A2C",
        blue = "#6E6A58",
        magenta = "#BFA75D",
        brown = "#c9926b",

        bright_red = "#D35F5F",
        bright_yellow = "#4D574E",
        bright_green = "#a3850e",
        bright_cyan = "#7A6A2C",
        bright_blue = "#6E6A58",
        bright_magenta = "#BFA75D",

        accent = "#6E6A58",
        cursor = "#F6F1DD",
        foreground = "#ebdbb2",
        background = "#000000",
        selection = "#241f16",
        selection_foreground = "#000000",
        selection_background = "#ebdbb2",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
