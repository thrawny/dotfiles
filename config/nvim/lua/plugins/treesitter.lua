-- All treesitter parsers ship prebuilt in the Nix store (nix/lib/nvim-package.nix);
-- there is no runtime parser installation to configure.
return {
  -- Disable treesitter textobjects move (]f, ]c, ]a etc.)
  -- Collides with codediff hunk navigation and never used
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    opts = { move = { enable = false } },
  },
}
