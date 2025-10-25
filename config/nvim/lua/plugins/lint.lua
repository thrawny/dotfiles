return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    -- Configure markdownlint
    local markdownlint = require("lint").linters["markdownlint-cli2"]
    markdownlint.args = {
      "--config",
      vim.json.encode({
        config = {
          MD013 = false,
        },
      }),
    }

    -- Disable SQL linting by default
    opts.linters_by_ft = opts.linters_by_ft or {}
    opts.linters_by_ft.sql = {}
    opts.linters_by_ft.mysql = {}
    opts.linters_by_ft.plsql = {}
  end,
}
