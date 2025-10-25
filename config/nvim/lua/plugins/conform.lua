return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    -- Override sqlfluff to use postgres dialect by default
    opts.formatters = opts.formatters or {}
    opts.formatters.sqlfluff = {
      args = { "format", "--dialect=postgres", "-" },
    }
  end,
}
