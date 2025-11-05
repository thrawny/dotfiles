return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      setup = {
        -- Drop semantic tokens (use Tree-sitter only) = fewer colors
        -- If you want to keep some, remove this block and see highlight links below.
        ["*"] = function(server, opts)
          local on_attach = opts.on_attach
          opts.on_attach = function(client, bufnr)
            if client.server_capabilities.semanticTokensProvider then
              client.server_capabilities.semanticTokensProvider = nil
            end
            if on_attach then
              on_attach(client, bufnr)
            end
          end
          require("lspconfig")[server].setup(opts)
          return true
        end,
      },
    },
  },
}
