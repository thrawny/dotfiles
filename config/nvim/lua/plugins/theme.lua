return {
  -- Monokai Pro theme with spectrum filter (colorblind-friendly)
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("monokai-pro").setup({
        filter = "spectrum",
        terminal_colors = true,
      })

      -- Load the colorscheme first
      vim.cmd.colorscheme("monokai-pro")

      -- Apply custom colorblind-friendly highlights after colorscheme loads
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "monokai-pro",
        callback = function()
          -- Spectrum palette colors
          local yellow = "#fce566"
          local cyan = "#5ad4e6"
          local purple = "#948ae3"
          local pink = "#fc618d"
          local white = "#f7f1ff"
          local bg = "#222222"

          local highlights = {
            -- Variables stay neutral (white/text color)
            ["@variable"] = { fg = white },
            ["@variable.member"] = { fg = purple },
            ["@parameter"] = { fg = white },

            -- Properties/fields in purple (like Darcula)
            ["@property"] = { fg = purple },
            ["@field"] = { fg = purple },

            -- Functions in yellow/gold (like Darcula)
            ["@function"] = { fg = yellow },
            ["@function.call"] = { fg = yellow },
            ["@method"] = { fg = yellow },
            ["@method.call"] = { fg = yellow },
            ["@function.method.call"] = { fg = yellow },
            ["@function.method"] = { fg = yellow },

            -- Types/structs in cyan (like Darcula)
            ["@type"] = { fg = cyan },
            ["@type.builtin"] = { fg = cyan },

            -- Strings in yellow, numbers in purple
            ["@string"] = { fg = yellow },
            ["@constant"] = { fg = yellow },
            ["@number"] = { fg = purple },

            -- Keywords in pink/red
            ["@keyword"] = { fg = pink },

            -- Functions and methods
            -- LSP semantic token overrides (higher priority than treesitter)
            ["@lsp.type.function"] = { fg = yellow },
            ["@lsp.type.method"] = { fg = yellow },

            -- Variables (keep neutral/white)
            ["@lsp.type.variable"] = { fg = white },
            ["@lsp.type.parameter"] = { fg = white },
            ["@lsp.type.namespace"] = { fg = white },
            ["@lsp.type.module"] = { fg = white },

            -- Properties/fields in purple
            ["@lsp.type.property"] = { fg = purple },
            ["@lsp.type.field"] = { fg = purple },

            -- Types in cyan
            ["@lsp.type.type"] = { fg = cyan },
            ["@lsp.type.struct"] = { fg = cyan },
            ["@lsp.type.class"] = { fg = cyan },
            ["@lsp.type.interface"] = { fg = cyan },
            ["@lsp.type.enum"] = { fg = cyan },
            ["@lsp.type.typeParameter"] = { fg = cyan },

            -- Colorblind-friendly diffs (avoid red/green contrast)
            DiffAdd = { bg = bg, fg = cyan },
            DiffDelete = { bg = bg, fg = pink },
            DiffChange = { bg = bg, fg = yellow },
            GitSignsAdd = { fg = cyan },
            GitSignsChange = { fg = yellow },
            GitSignsDelete = { fg = pink },
          }

          for group, colors in pairs(highlights) do
            vim.api.nvim_set_hl(0, group, colors)
          end
        end,
      })

      -- Trigger the autocmd manually on first load
      vim.cmd("doautocmd ColorScheme monokai-pro")
    end,
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
