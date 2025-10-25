return {
  -- Add monokai-nightasty theme to match Ghostty's Molokai theme
  {
    "polirritmico/monokai-nightasty.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      -- monokai-nightasty requires explicit load() call to apply terminal colors
      -- Disable terminal_colors so we can set them manually after load()
      require("monokai-nightasty").load({
        dark_style_background = "dark", -- dark, transparent, #color
        light_style_background = "default", -- default, dark, transparent, #color
        color_headers = false, -- Enable header colors for each header level (h1, h2, etc.)
        lualine_bold = true, -- Lualine headers will be bold or regular
        lualine_style = "default", -- "dark", "light" or "default" (Follows dark/light style)
        markdown_header_marks = false, -- Add headers marks highlights (the `#` character) to Treesitter highlight
        -- Style to be applied to different syntax groups
        hl_styles = {
          comments = { italic = true },
          keywords = { italic = false },
          functions = {},
          variables = {},
          -- Background styles for sidebars (panels) and floating windows:
          floats = "default", -- default, dark, transparent
          sidebars = "default", -- default, dark, transparent
        },
        sidebars = { "qf", "help", "terminal", "packer" }, -- Set a darker background on sidebar-like windows
        hide_inactive_statusline = false, -- Hide inactive statuslines and replace them with a thin border
        dim_inactive = false, -- dims inactive windows
        terminal_colors = false, -- Disable so we can set Molokai colors manually below
        -- --- You can override specific color groups to use other groups or a hex color
        -- --- function will be called with a ColorScheme table
        on_colors = function(colors) end,
        --- You can override specific highlights to use other groups or a hex color
        --- function will be called with a Highlights and ColorScheme table
        on_highlights = function(highlights, colors)
          -- Match Ghostty terminal background color
          local ghostty_bg = "#1c1c1c"
          highlights.Terminal = { bg = ghostty_bg }
          highlights.TerminalNC = { bg = ghostty_bg }
          -- Also make editor background match Ghostty for consistency
          highlights.Normal = { fg = colors.fg, bg = ghostty_bg }
          highlights.NormalFloat = { fg = colors.fg, bg = ghostty_bg }
        end,
      })

      -- Set terminal ANSI colors to match Ghostty's Molokai theme exactly
      -- Must be done AFTER load() to avoid being overwritten
      vim.g.terminal_color_0 = "#121212" -- Black
      vim.g.terminal_color_1 = "#fa2573" -- Red
      vim.g.terminal_color_2 = "#98e123" -- Green
      vim.g.terminal_color_3 = "#dfd460" -- Yellow
      vim.g.terminal_color_4 = "#1080d0" -- Blue
      vim.g.terminal_color_5 = "#8700ff" -- Magenta
      vim.g.terminal_color_6 = "#43a8d0" -- Cyan
      vim.g.terminal_color_7 = "#bbbbbb" -- White
      vim.g.terminal_color_8 = "#555555" -- Bright Black
      vim.g.terminal_color_9 = "#f6669d" -- Bright Red
      vim.g.terminal_color_10 = "#b1e05f" -- Bright Green
      vim.g.terminal_color_11 = "#fff26d" -- Bright Yellow
      vim.g.terminal_color_12 = "#00afff" -- Bright Blue
      vim.g.terminal_color_13 = "#af87ff" -- Bright Magenta
      vim.g.terminal_color_14 = "#51ceff" -- Bright Cyan
      vim.g.terminal_color_15 = "#ffffff" -- Bright White
    end,
  },

  -- Configure LazyVim to load monokai-nightasty
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-nightasty",
    },
  },
}
