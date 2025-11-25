return {
  dir = "~/stuff/magenta.nvim",
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
    editPrediction = {
      profile = {
        provider = "anthropic",
        model = "claude-haiku-4-5-20251001",
        authType = "max",
      },
    },
  },
  keys = {
    { "<leader>aa", "<cmd>Magenta predict-edit<cr>", desc = "Magenta predict edit" },
  },
}
