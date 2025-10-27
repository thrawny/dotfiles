return {
  -- Disable yamlls LSP formatting (it auto-indents sequences which we don't want)
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = {
          settings = {
            yaml = {
              format = {
                enable = false, -- Disable auto-formatting
              },
            },
          },
        },
      },
    },
  },
}
