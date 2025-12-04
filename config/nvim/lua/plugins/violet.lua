return {
  "thrawny/violet.nvim",
  enabled = dev_plugin_exists("violet.nvim"),
  dev = true,
  dependencies = {},
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
  },
  config = function()
    require("violet").setup()
  end,
}
