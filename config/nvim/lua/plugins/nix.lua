-- Nix language support (only enabled if nixd is available)
local has_nixd = vim.fn.executable("nixd") == 1

if not has_nixd then
  return {}
end

return {
  -- Import LazyVim nix extra for treesitter, etc.
  { import = "lazyvim.plugins.extras.lang.nix" },

  -- Override LSP to use nixd instead of nil_ls
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = {
          settings = {
            nixd = {
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
