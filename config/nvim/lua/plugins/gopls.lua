return {
  "neovim/nvim-lspconfig",
  opts = {
    setup = {
      gopls = function(server, opts)
        Snacks.util.lsp.on({ name = "gopls" }, function(_, client)
          local semantic = vim.tbl_get(client.config, "capabilities", "textDocument", "semanticTokens")
          if semantic and not client.server_capabilities.semanticTokensProvider then
            client.server_capabilities.semanticTokensProvider = {
              full = true,
              legend = {
                tokenTypes = semantic.tokenTypes,
                tokenModifiers = semantic.tokenModifiers,
              },
              range = true,
            }
          end
        end)
        vim.lsp.config(server, opts)
        vim.lsp.enable(server)
        return true
      end,
    },
    servers = {
      gopls = {
        settings = {
          gopls = {
            usePlaceholders = false,
            analyses = {
              ST1000 = false,
              ST1003 = false,
            },
          },
        },
      },
    },
  },
}
