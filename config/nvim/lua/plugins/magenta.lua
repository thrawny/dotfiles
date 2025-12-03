return {
  "dlants/magenta.nvim",
  dev = vim.fn.isdirectory(vim.g.dev_path .. "/magenta.nvim") == 1,
  lazy = false,
  build = "npm ci",
  opts = {
    profiles = {
      {
        name = "claude-max",
        provider = "anthropic",
        model = "claude-opus-4-5-20251101",
        fastModel = "claude-haiku-4-5-20251001",
        authType = "max",
      },
    },
    defaultProfile = "claude-max",
  },
  keys = {
    { "<leader>aa", "<cmd>Magenta predict-edit<cr>", desc = "Magenta predict edit" },
    {
      "<Tab>",
      function()
        local magenta = require("magenta")
        if magenta.has_prediction and magenta.has_prediction() then
          vim.cmd("Magenta accept-prediction")
        end
      end,
      desc = "Accept Magenta prediction",
      mode = "n",
    },
  },
}
