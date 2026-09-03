-- Nix supplies editor tools itself. The portable macOS setup uses Mason.
local nix_package = vim.env.DOTFILES_PORTABLE ~= "1" and vim.v.progpath:find("/nix/store/", 1, true) ~= nil

return {
  { "mason-org/mason.nvim", enabled = not nix_package },
  { "mason-org/mason-lspconfig.nvim", enabled = not nix_package },
}
