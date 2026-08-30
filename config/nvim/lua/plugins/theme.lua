local theme = require("config.theme").load()

return {
  -- Monokai Pro theme with spectrum filter (colorblind-friendly)
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      local sem = theme.semantic
      local syn = theme.syntax
      local diff = theme.diff
      local app = theme.applications.nvim

      local bg = sem.background
      require("monokai-pro").setup({
        filter = "spectrum",
        terminal_colors = false,
        override = function(c)
          return {
            -- Set backgrounds for normal windows and terminals to match theme
            Normal = { fg = c.base.white, bg = bg },
            NormalNC = { fg = c.base.white, bg = bg },
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
          -- Roles from the central theme (spectrum palette)
          local yellow = syn["function"]
          local cyan = syn.type
          local purple = syn.number
          local pink = syn.keyword
          local orange = sem.warning
          local white = sem.foreground
          local green = app.bashString

          local highlights = {
            -- Float window borders (LSP hover, etc.)
            FloatBorder = { fg = sem.dim, bg = bg },

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

            -- No @lsp.* groups here: semantic-token highlighting is disabled
            -- (lsp.lua clears every @lsp group), so treesitter colors are the
            -- single source of truth.

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

            -- TypeScript/JavaScript constants in purple
            ["@constant.typescript"] = { fg = purple },
            ["@constant.javascript"] = { fg = purple },

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

            -- Colorblind-friendly diffs (avoid red/green contrast)
            DiffAdd = { bg = bg, fg = diff.added.foreground },
            DiffDelete = { bg = bg, fg = diff.removed.foreground },
            DiffChange = { bg = bg, fg = diff.changed.foreground },
            GitSignsAdd = { fg = diff.added.foreground },
            GitSignsChange = { fg = diff.changed.foreground },
            GitSignsDelete = { fg = diff.removed.foreground },

            -- codediff explorer selected file
            CodeDiffExplorerSelected = { bg = app.explorerSelection },

            -- Snacks file explorer
            SnacksPickerDirectory = { fg = purple, bold = true },
            SnacksPickerFile = { fg = white },
            SnacksPickerDir = { fg = sem.muted }, -- dimmed gray for path portions
            SnacksPickerPathHidden = { fg = sem.dim }, -- darker gray for hidden files
            SnacksPickerPathIgnored = { fg = sem.dim }, -- darker gray for ignored files
            SnacksPickerTree = { fg = sem.dim }, -- tree indent lines
            SnacksPickerLink = { fg = purple }, -- symlinks in purple
            SnacksPickerLinkBroken = { fg = pink }, -- broken links in pink

            -- Snacks git status
            SnacksPickerGitStatusAdded = { fg = sem.success },
            SnacksPickerGitStatusModified = { fg = yellow },
            SnacksPickerGitStatusDeleted = { fg = pink },
            SnacksPickerGitStatusRenamed = { fg = yellow },
            SnacksPickerGitStatusUntracked = { fg = purple },
            SnacksPickerGitStatusIgnored = { fg = sem.dim },
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

      -- Terminal ANSI colors from the central theme
      for i, color in ipairs(theme.terminal.normal) do
        vim.g["terminal_color_" .. (i - 1)] = color
      end
      for i, color in ipairs(theme.terminal.bright) do
        vim.g["terminal_color_" .. (i + 7)] = color
      end
    end,
  },

  -- Configure LazyVim to load monokai-pro
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-pro",
    },
  },
}
