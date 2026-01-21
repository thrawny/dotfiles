-- Nix LSP override: use nixd instead of nil_ls
-- Note: The lazyvim nix extra is conditionally imported in lazy.lua
local has_nixd = vim.fn.executable("nixd") == 1

if not has_nixd then
  return {}
end

return {
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
