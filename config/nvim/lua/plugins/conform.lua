return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    -- Override sqlfluff to use postgres dialect by default
    opts.formatters = opts.formatters or {}
    opts.formatters.sqlfluff = {
      args = { "format", "--dialect=postgres", "-" },
    }

    -- Enable sqlfluff for SQL files (manual formatting only)
    opts.formatters_by_ft = opts.formatters_by_ft or {}
    opts.formatters_by_ft.sql = { "sqlfluff" }

    -- Disable formatting for YAML files (Prettier doesn't support custom sequence indentation)
    opts.formatters_by_ft.yaml = {}
  end,
}
