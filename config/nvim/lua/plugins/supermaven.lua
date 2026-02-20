return {
  {
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
    config = function(_, opts)
      require("supermaven-nvim").setup(opts)
      -- Start disabled — toggle on with <leader>as
      require("supermaven-nvim.api").stop()
    end,
    keys = {
      {
        "<leader>as",
        function()
          local api = require("supermaven-nvim.api")
          api.toggle()
          local enabled = api.is_running()
          vim.notify(
            enabled and "Supermaven enabled" or "Supermaven disabled",
            vim.log.levels.INFO,
            { title = "Supermaven" }
          )
        end,
        desc = "Toggle Supermaven",
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, {
        function()
          return "SM"
        end,
        cond = function()
          local ok, api = pcall(require, "supermaven-nvim.api")
          return ok and api.is_running()
        end,
        color = { fg = "#948ae3" },
      })
    end,
  },
}
