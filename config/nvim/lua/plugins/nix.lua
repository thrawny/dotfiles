-- Nix LSP override: use nixd instead of nil_ls (the lang.nix extra is
-- imported unconditionally in nix/lib/nvim-package.nix; nixd comes from
-- the shared Home Manager packages)
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = {
          settings = {
            nixd = {
              diagnostic = {
                suppress = { "sema-unused-def-lambda-noarg-formal" },
              },
              formatting = {
                command = { "nixfmt" },
              },
            },
          },
        },
      },
    },
  },
}
