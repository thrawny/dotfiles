return {
  -- Disable bufferline (top tab view)
  {
    "akinsho/bufferline.nvim",
    enabled = false,
  },

  -- Configure noice for LSP hover borders
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        lsp_doc_border = true,
      },
    },
  },

  -- Configure snacks explorer to show hidden and ignored files by default
  {
    "snacks.nvim",
    keys = {
      {
        "<M-;>",
        function()
          Snacks.terminal(nil, { cwd = LazyVim.root() })
        end,
        mode = { "n", "t" },
        desc = "Terminal (Root Dir)",
      },
      {
        "<leader>ge",
        function()
          Snacks.picker.git_status({ ignored = false })
        end,
        desc = "Git Status (Explorer)",
      },
      {
        "<leader>`",
        function()
          Snacks.scratch()
        end,
        desc = "Scratch Buffer",
      },
    },
    opts = {
      picker = {
        hidden = true, -- Show hidden files by default
        ignored = true, -- Show gitignored files by default
        exclude = { ".DS_Store" },
      },
      terminal = {
        win = {
          keys = {
            -- Add M-; as a hide action when in terminal mode (same as C-/)
            hide_alt_semicolon = { "<M-;>", "hide", desc = "Hide Terminal", mode = { "t", "n" } },
          },
        },
      },
      lazygit = {
        win = {
          width = 0,
          height = 0,
        },
      },
    },
  },
}
