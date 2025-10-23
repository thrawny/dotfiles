return {
  -- Disable bufferline (top tab view)
  {
    "akinsho/bufferline.nvim",
    enabled = false,
  },

  -- Configure snacks explorer to show hidden and ignored files by default
  {
    "snacks.nvim",
    opts = {
      picker = {
        hidden = true, -- Show hidden files by default
        ignored = true, -- Show gitignored files by default
        exclude = { ".DS_Store" },
      },
    },
  },
}
