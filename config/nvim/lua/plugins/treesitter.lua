return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Skip treesitter installation on headless servers (low memory)
      -- Using a function to override LazyVim's defaults instead of merging
      if vim.env.NVIM_HEADLESS then
        opts.ensure_installed = {}
      else
        opts.ensure_installed = {
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
      end
      opts.auto_install = false
    end,
  },
}
