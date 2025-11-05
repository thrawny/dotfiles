return {
  -- Monokai Pro theme with spectrum filter (colorblind-friendly)
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      filter = "spectrum",
      terminal_colors = true,
    },
  },

  -- Configure LazyVim to load monokai-pro
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-pro",
    },
  },

  -- Previous theme (monokai-nightasty) - kept for reference
  -- Uncomment to switch back
  -- {
  --   "polirritmico/monokai-nightasty.nvim",
  --   lazy = false,
  --   priority = 1000,
  --   config = function()
  --     require("monokai-nightasty").load({
  --       dark_style_background = "dark",
  --       light_style_background = "default",
  --       color_headers = false,
  --       lualine_bold = true,
  --       lualine_style = "default",
  --       markdown_header_marks = false,
  --       hl_styles = {
  --         comments = { italic = true },
  --         keywords = { italic = false },
  --         functions = {},
  --         variables = {},
  --         floats = "default",
  --         sidebars = "default",
  --       },
  --       sidebars = { "qf", "help", "terminal", "packer" },
  --       hide_inactive_statusline = false,
  --       dim_inactive = false,
  --       terminal_colors = false,
  --       on_colors = function(colors) end,
  --       on_highlights = function(highlights, colors)
  --         local ghostty_bg = "#1c1c1c"
  --         highlights.Terminal = { bg = ghostty_bg }
  --         highlights.TerminalNC = { bg = ghostty_bg }
  --         highlights.Normal = { fg = colors.fg, bg = ghostty_bg }
  --         highlights.NormalFloat = { fg = colors.fg, bg = ghostty_bg }
  --       end,
  --     })
  --
  --     -- Terminal ANSI colors matching Ghostty's Molokai theme
  --     vim.g.terminal_color_0 = "#121212"
  --     vim.g.terminal_color_1 = "#fa2573"
  --     vim.g.terminal_color_2 = "#98e123"
  --     vim.g.terminal_color_3 = "#dfd460"
  --     vim.g.terminal_color_4 = "#1080d0"
  --     vim.g.terminal_color_5 = "#8700ff"
  --     vim.g.terminal_color_6 = "#43a8d0"
  --     vim.g.terminal_color_7 = "#bbbbbb"
  --     vim.g.terminal_color_8 = "#555555"
  --     vim.g.terminal_color_9 = "#f6669d"
  --     vim.g.terminal_color_10 = "#b1e05f"
  --     vim.g.terminal_color_11 = "#fff26d"
  --     vim.g.terminal_color_12 = "#00afff"
  --     vim.g.terminal_color_13 = "#af87ff"
  --     vim.g.terminal_color_14 = "#51ceff"
  --     vim.g.terminal_color_15 = "#ffffff"
  --   end,
  -- },
  --
  -- -- To use monokai-nightasty, also change LazyVim colorscheme above to:
  -- -- colorscheme = "monokai-nightasty",
}
