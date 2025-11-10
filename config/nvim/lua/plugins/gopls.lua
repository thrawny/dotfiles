return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      gopls = {
        settings = {
          gopls = {
            usePlaceholders = false,
            analyses = {
              ST1000 = false,
            },
          },
        },
      },
    },
  },
}
