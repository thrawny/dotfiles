return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    opts.formatters = opts.formatters or {}
    opts.formatters_by_ft = opts.formatters_by_ft or {}

    -- Use golangci-lint for Go formatting (respects .golangci.yaml config)
    opts.formatters_by_ft.go = { "golangci-lint" }

    -- Override sqlfluff to use postgres dialect by default
    opts.formatters.sqlfluff = {
      args = { "format", "--dialect=postgres", "-" },
      cwd = require("conform.util").root_file({}), -- Don't require a root directory
      require_cwd = false, -- Allow formatting even without a project root
    }

    -- Enable sqlfluff for SQL files (manual formatting only)
    opts.formatters_by_ft.sql = { "sqlfluff" }

    -- Disable formatting for YAML files (Prettier doesn't support custom sequence indentation)
    opts.formatters_by_ft.yaml = {}

    -- Use biome for JSON (autoformat disabled via autocmds.lua)
    opts.formatters_by_ft.json = { "biome" }
    opts.formatters_by_ft.jsonc = { "biome" }
    opts.formatters.biome = {
      require_cwd = false,
    }

    -- Use shfmt with 4-space indentation for bash/shell files
    opts.formatters.shfmt = {
      append_args = { "-i", "4" },
    }
  end,
}
