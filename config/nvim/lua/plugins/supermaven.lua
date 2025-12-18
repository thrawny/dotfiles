return {
  "supermaven-inc/supermaven-nvim",
  init = function()
    vim.api.nvim_set_hl(0, "SupermavenSuggestion", { fg = "#69676c" })
  end,
  keys = {
    {
      "<leader>as",
      function()
        require("supermaven-nvim.api").toggle()
      end,
      desc = "Toggle Supermaven",
    },
  },
}
