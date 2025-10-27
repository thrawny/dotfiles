return {
  {
    "folke/edgy.nvim",
    optional = true,
    opts = function(_, opts)
      -- Move DBUI to the left sidebar instead of right
      opts.left = opts.left or {}
      table.insert(opts.left, {
        title = "Database",
        ft = "dbui",
        pinned = true,
        width = 0.3,
        open = function()
          vim.cmd("DBUI")
        end,
      })

      opts.bottom = opts.bottom or {}
      table.insert(opts.bottom, {
        title = "DB Query Result",
        ft = "dbout",
      })
    end,
  },
}
