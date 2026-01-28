-- Nix compatibility: disable Mason on NixOS/Nix (LSPs provided by Nix)

if vim.fn.isdirectory("/nix") == 0 then
  return {} -- Non-Nix: keep Mason
end

return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}
