return {
  -- Disable bufferline (top tab view)
  {
    "akinsho/bufferline.nvim",
    enabled = false,
  },

  -- Configure neo-tree to show hidden files
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true, -- Show hidden files
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
    },
  },
}
