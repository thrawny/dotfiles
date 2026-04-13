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
      keymaps = {
        view = {
          next_hunk = "}",
          prev_hunk = "{",
        },
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

  -- Remap {/} to hunk navigation in normal buffers (gitsigns)
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      ---@diagnostic disable-next-line: param-type-mismatch
      { "}", function() require("gitsigns").nav_hunk("next") end, desc = "Next Hunk" },
      ---@diagnostic disable-next-line: param-type-mismatch
      { "{", function() require("gitsigns").nav_hunk("prev") end, desc = "Prev Hunk" },
    },
  },
}
