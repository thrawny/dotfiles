return {
  {
    "klepp0/nvim-baml-syntax",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("baml_syntax").setup()
    end,
  },
}
