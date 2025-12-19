return {
  "thrawny/violet.nvim",
  enabled = dev_plugin_exists("violet.nvim"),
  dev = true,
  dependencies = {},
  lazy = false,
  keys = {
    {
      "<leader>ai",
      function()
        require("violet").inline_edit()
      end,
      desc = "Inline Edit",
    },
    {
      "<leader>ai",
      function()
        require("violet").inline_edit_selection()
      end,
      mode = "v",
      desc = "Inline Edit Selection",
    },
    {
      "<leader>an",
      function()
        require("violet").edit_prediction()
      end,
      desc = "Edit Prediction",
    },
  },
  config = function()
    require("violet").setup()
  end,
}
