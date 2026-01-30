return {
  "supermaven-inc/supermaven-nvim",
  init = function()
    vim.api.nvim_set_hl(0, "SupermavenSuggestion", { fg = "#69676c" })
  end,
  event = "BufReadPost",
  opts = {
    -- condition returns true to DISABLE supermaven for the buffer
    condition = function()
      return vim.tbl_contains({ ".env", ".env.local", ".envrc", ".zsh.local" }, vim.fn.expand("%:t"))
    end,
  },
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
