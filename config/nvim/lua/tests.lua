local M = {}

local suites = {
  require("tests.sql_selection"),
}

function M.run_all()
  local failures = {}
  local passed = 0
  local total = 0

  for _, suite in ipairs(suites) do
    for _, test in ipairs(suite.tests) do
      total = total + 1
      local label = string.format("%s.%s", suite.name, test.name)
      local ok, err = xpcall(test.fn, debug.traceback)
      if ok then
        passed = passed + 1
        vim.api.nvim_out_write("PASS " .. label .. "\n")
      else
        failures[#failures + 1] = { label = label, err = err }
        vim.api.nvim_err_writeln("FAIL " .. label)
        vim.api.nvim_err_writeln(err)
      end
    end
  end

  vim.api.nvim_out_write(string.format("RESULT %d/%d passed\n", passed, total))

  if #failures > 0 then
    error(string.format("%d test(s) failed", #failures))
  end
end

return M
