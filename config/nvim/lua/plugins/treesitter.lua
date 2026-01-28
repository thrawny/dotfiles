-- Skip treesitter installation on headless servers (low memory)
local ensure_installed = vim.env.NVIM_HEADLESS and {}
  or {
    "bash",
    "c",
    "go",
    "gomod",
    "gosum",
    "javascript",
    "json",
    "lua",
    "markdown",
    "markdown_inline",
    "nix",
    "python",
    "rust",
    "sql",
    "terraform",
    "toml",
    "tsx",
    "typescript",
    "vim",
    "vimdoc",
    "yaml",
  }

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = ensure_installed,
      auto_install = false,
    },
  },
}
