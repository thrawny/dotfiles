return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    opts.linters_by_ft = opts.linters_by_ft or {}
    -- Disable markdown linting (markdownlint-cli2 not installed)
    opts.linters_by_ft.markdown = {}
    -- Disable SQL linting
    opts.linters_by_ft.sql = {}
    opts.linters_by_ft.mysql = {}
    opts.linters_by_ft.plsql = {}
  end,
}
