local function golangcilint_target()
  local filename = vim.api.nvim_buf_get_name(0)
  local dirname = vim.fn.fnamemodify(filename, ":h")

  local ok, result = pcall(function()
    return vim.system({ "go", "env", "GOMOD", "GOWORK" }, { cwd = dirname, text = true }):wait()
  end)
  if ok and result.code == 0 then
    local lines = vim.split(vim.trim(result.stdout or ""), "\n", { plain = true })
    local gomod = vim.trim(lines[1] or "")
    local gowork = vim.trim(lines[2] or "")
    local has_module = gomod ~= "" and gomod ~= "/dev/null"
    local has_workspace = gowork ~= "" and gowork ~= "off" and gowork ~= "/dev/null"

    if has_module or has_workspace then
      return dirname
    end
  end

  -- Fall back to single-file linting for standalone Go files.
  return vim.fn.fnamemodify(filename, ":p")
end

local function golangcilint_linter()
  local linter = require("lint.linters.golangcilint")
  if linter.args and #linter.args > 0 then
    linter.args[#linter.args] = golangcilint_target
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
