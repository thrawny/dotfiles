return {
  -- Monokai Pro theme with spectrum filter (colorblind-friendly)
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("monokai-pro").setup({
        filter = "spectrum",
        terminal_colors = false,
        override = function(c)
          local bg = "#222222"
          return {
            -- Set backgrounds for normal windows and terminals to match theme
            Normal = { fg = c.base.white, bg = bg },
            NormalFloat = { fg = c.base.white, bg = bg },
            Terminal = { bg = bg },
            TerminalNC = { bg = bg },
          }
        end,
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
          local orange = "#fc9867"
          local white = "#f7f1ff"
          local green = "#678256"
          local bg = "#222222"

          local highlights = {
            -- Disable italics globally
            Comment = { italic = false },
            ["@comment"] = { italic = false },
            ["@lsp.type.comment"] = { italic = false },

            -- Float window borders (LSP hover, etc.)
            FloatBorder = { fg = "#69676c", bg = bg },

            -- Variables stay neutral (white/text color)
            ["@variable"] = { fg = white },
            ["@variable.member"] = { fg = purple },
            ["@variable.parameter"] = { fg = orange, italic = false },
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
            ["@keyword"] = { fg = pink, italic = false },
            ["@keyword.lua"] = { fg = pink, italic = false },

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

            -- Bash (Dracula-style)
            ["@function.bash"] = { fg = yellow },
            ["@function.call.bash"] = { fg = yellow },
            ["@function.builtin.bash"] = { fg = yellow },
            ["@keyword.bash"] = { fg = orange },
            ["@keyword.conditional.bash"] = { fg = orange },
            ["@keyword.repeat.bash"] = { fg = orange },
            ["@constant.bash"] = { fg = white },
            ["@variable.bash"] = { fg = white },
            ["@string.bash"] = { fg = green },

            -- Python (minimal colorblind-friendly: white/yellow/cyan/pink/purple only)
            ["@variable.python"] = { fg = white },
            ["@variable.member.python"] = { fg = white },
            ["@variable.parameter.python"] = { fg = white },
            ["@field.python"] = { fg = white },
            ["@property.python"] = { fg = white },
            ["@constant.python"] = { fg = purple },
            ["@constant.builtin.python"] = { fg = purple },
            ["@function.python"] = { fg = yellow },
            ["@function.call.python"] = { fg = yellow },
            ["@function.method.python"] = { fg = yellow },
            ["@function.method.call.python"] = { fg = yellow },
            ["@function.builtin.python"] = { fg = yellow },
            ["@type.python"] = { fg = cyan, italic = false },
            ["@type.builtin.python"] = { fg = cyan },
            ["@keyword.python"] = { fg = pink, italic = false },
            ["@keyword.type.python"] = { fg = pink, italic = false },
            ["@keyword.function.python"] = { fg = pink, italic = false },
            ["@keyword.return.python"] = { fg = pink, italic = false },
            ["@keyword.import.python"] = { fg = pink, italic = false },
            ["@string.python"] = { fg = yellow },
            ["@module.python"] = { fg = white },
            ["@attribute.python"] = { fg = yellow },
            ["@decorator.python"] = { fg = yellow },
            ["@constructor.python"] = { fg = cyan },

            -- Python LSP semantic tokens
            ["@lsp.type.variable.python"] = { fg = white },
            ["@lsp.type.parameter.python"] = { fg = white },
            ["@lsp.type.property.python"] = { fg = white },
            ["@lsp.type.function.python"] = { fg = yellow },
            ["@lsp.type.method.python"] = { fg = yellow },
            ["@lsp.type.class.python"] = { fg = cyan },
            ["@lsp.type.namespace.python"] = { fg = white },

            -- Rust (minimal colors like Python)
            ["@variable.rust"] = { fg = white },
            ["@variable.member.rust"] = { fg = white },
            ["@variable.parameter.rust"] = { fg = white },
            ["@field.rust"] = { fg = white },
            ["@property.rust"] = { fg = white },
            ["@constant.rust"] = { fg = purple },
            ["@constant.builtin.rust"] = { fg = purple },
            ["@function.rust"] = { fg = yellow },
            ["@function.call.rust"] = { fg = yellow },
            ["@function.method.rust"] = { fg = yellow },
            ["@function.method.call.rust"] = { fg = yellow },
            ["@function.macro.rust"] = { fg = yellow },
            ["@type.rust"] = { fg = cyan },
            ["@type.builtin.rust"] = { fg = cyan },
            ["@keyword.rust"] = { fg = pink, italic = false },
            ["@keyword.function.rust"] = { fg = pink, italic = false },
            ["@keyword.return.rust"] = { fg = pink, italic = false },
            ["@string.rust"] = { fg = yellow },
            ["@punctuation.bracket.rust"] = { fg = white },
            ["@punctuation.delimiter.rust"] = { fg = white },
            ["@operator.rust"] = { fg = pink },
            ["@module.rust"] = { fg = white },
            ["@namespace.rust"] = { fg = white },

            -- Rust LSP semantic tokens (override rust-analyzer's colorful defaults)
            ["@lsp.type.variable.rust"] = { fg = white },
            ["@lsp.type.parameter.rust"] = { fg = white },
            ["@lsp.type.property.rust"] = { fg = white },
            ["@lsp.type.enumMember.rust"] = { fg = purple },
            ["@lsp.type.function.rust"] = { fg = yellow },
            ["@lsp.type.method.rust"] = { fg = yellow },
            ["@lsp.type.macro.rust"] = { fg = yellow },
            ["@lsp.type.namespace.rust"] = { fg = white },
            ["@lsp.type.struct.rust"] = { fg = cyan },
            ["@lsp.type.enum.rust"] = { fg = cyan },
            ["@lsp.type.interface.rust"] = { fg = cyan },
            ["@lsp.type.typeAlias.rust"] = { fg = cyan },
            ["@lsp.type.selfKeyword.rust"] = { fg = pink },
            ["@lsp.type.selfTypeKeyword.rust"] = { fg = cyan },
            ["@lsp.type.lifetime.rust"] = { fg = pink },
            ["@lsp.type.formatSpecifier.rust"] = { fg = yellow },
            ["@lsp.mod.mutable.rust"] = {},
            ["@lsp.mod.reference.rust"] = {},
            ["@lsp.mod.consuming.rust"] = {},

            -- Colorblind-friendly diffs (avoid red/green contrast)
            DiffAdd = { bg = bg, fg = cyan },
            DiffDelete = { bg = bg, fg = pink },
            DiffChange = { bg = bg, fg = yellow },
            GitSignsAdd = { fg = cyan },
            GitSignsChange = { fg = yellow },
            GitSignsDelete = { fg = pink },

            -- Snacks file explorer
            SnacksPickerDirectory = { fg = purple, bold = true },
            SnacksPickerFile = { fg = white },
            SnacksPickerDir = { fg = "#8b888f" }, -- dimmed gray for path portions
            SnacksPickerPathHidden = { fg = "#69676c" }, -- darker gray for hidden files
            SnacksPickerPathIgnored = { fg = "#69676c" }, -- darker gray for ignored files
            SnacksPickerTree = { fg = "#69676c" }, -- tree indent lines
            SnacksPickerLink = { fg = purple }, -- symlinks in purple
            SnacksPickerLinkBroken = { fg = pink }, -- broken links in pink

            -- Snacks git status
            SnacksPickerGitStatusAdded = { fg = "#7bd88f" }, -- green
            SnacksPickerGitStatusModified = { fg = yellow },
            SnacksPickerGitStatusDeleted = { fg = pink },
            SnacksPickerGitStatusRenamed = { fg = yellow },
            SnacksPickerGitStatusUntracked = { fg = purple },
            SnacksPickerGitStatusIgnored = { fg = "#69676c" },
            SnacksPickerGitStatusUnmerged = { fg = pink }, -- conflicts
            SnacksPickerGitStatusStaged = { fg = cyan },
          }

          for group, colors in pairs(highlights) do
            vim.api.nvim_set_hl(0, group, colors)
          end
        end,
      })

      -- Trigger the autocmd manually on first load
      vim.cmd("doautocmd ColorScheme monokai-pro")

      -- Terminal ANSI colors using monokai-pro spectrum palette
      vim.g.terminal_color_0 = "#121212" -- black
      vim.g.terminal_color_1 = "#fc618d" -- red (pink from spectrum)
      vim.g.terminal_color_2 = "#98e123" -- green
      vim.g.terminal_color_3 = "#fce566" -- yellow (from spectrum)
      vim.g.terminal_color_4 = "#5ad4e6" -- blue (cyan from spectrum)
      vim.g.terminal_color_5 = "#948ae3" -- magenta (purple from spectrum)
      vim.g.terminal_color_6 = "#5ad4e6" -- cyan (from spectrum)
      vim.g.terminal_color_7 = "#bbbbbb" -- white/light gray
      vim.g.terminal_color_8 = "#555555" -- bright black (gray)
      vim.g.terminal_color_9 = "#ff87a8" -- bright red (lighter pink)
      vim.g.terminal_color_10 = "#b1e05f" -- bright green
      vim.g.terminal_color_11 = "#fef87e" -- bright yellow
      vim.g.terminal_color_12 = "#7de4f0" -- bright blue (lighter cyan)
      vim.g.terminal_color_13 = "#b5b0f0" -- bright magenta (lighter purple)
      vim.g.terminal_color_14 = "#7de4f0" -- bright cyan
      vim.g.terminal_color_15 = "#f7f1ff" -- bright white (from spectrum)
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
