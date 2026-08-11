local go_workspace = require("config.go_workspace")

local function golangcilint_linter()
  local linter = vim.deepcopy(require("lint.linters.golangcilint"))
  local context = go_workspace.context(vim.api.nvim_buf_get_name(0))
  linter.cwd = context.cwd
  linter.env = context.env
  if linter.args and #linter.args > 0 then
    linter.args[#linter.args] = context.target
  end
  return linter
end

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

    opts.linters = opts.linters or {}
    opts.linters.golangcilint = golangcilint_linter
  end,
}
