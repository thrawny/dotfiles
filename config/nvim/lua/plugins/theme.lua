return {
  -- Add monokai-nightasty theme to match Ghostty's Molokai theme
  {
    "polirritmico/monokai-nightasty.nvim",
    lazy = false,
    priority = 1000,
    opts = {
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
      terminal_colors = true, -- Configure the colors used when opening a `:terminal`
      -- --- You can override specific color groups to use other groups or a hex color
      -- --- function will be called with a ColorScheme table
      on_colors = function(colors) end,
      --- You can override specific highlights to use other groups or a hex color
      --- function will be called with a Highlights and ColorScheme table
      on_highlights = function(highlights, colors) end,
    },
  },

  -- Configure LazyVim to load monokai-nightasty
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-nightasty",
    },
  },
}
