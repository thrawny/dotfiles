-- Mason is disabled: language servers, formatters, and linters are provided
-- by the shared Home Manager package sets (the editor itself only exists as a
-- Nix package, so there is no non-Nix environment to support).
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}
