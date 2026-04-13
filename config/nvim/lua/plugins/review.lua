return {
  {
    "esmuellert/codediff.nvim",
    opts = {
      highlights = {
        line_insert = "#004466",
        line_delete = "#660100",
        char_insert = "#0077b3",
        char_delete = "#b30100",
      },
    },
  },

  {
    "georgeguimaraes/review.nvim",
    dependencies = {
      "esmuellert/codediff.nvim",
      "MunifTanjim/nui.nvim",
    },
    cmd = { "Review" },
    keys = {
      { "<leader>r", "<cmd>Review<cr>", desc = "Review" },
      { "<leader>R", "<cmd>Review commits<cr>", desc = "Review commits" },
    },
    opts = {},

  },
}
