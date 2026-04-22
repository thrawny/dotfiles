local M = {
  name = "sql_selection",
  tests = {},
}

local select_sql_statement = require("config.sql_selection").select_sql_statement

local function fake_node(node_type, range, parent)
  return {
    type = function()
      return node_type
    end,
    range = function()
      return unpack(range)
    end,
    parent = function()
      return parent
    end,
  }
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(
      (message or "assertion failed")
        .. string.format("\nexpected: %s\nactual: %s", vim.inspect(expected), vim.inspect(actual))
    )
  end
end

local function get_selected_text()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

  if #lines == 0 then
    return ""
  end

  lines[1] = lines[1]:sub(start_pos[3])
  lines[#lines] = lines[#lines]:sub(1, end_pos[3])
  return table.concat(lines, "\n")
end

local function with_scratch_buffer(lines, cursor, fn)
  local previous_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "sql"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, cursor)

  local ok, result = xpcall(fn, debug.traceback)

  vim.api.nvim_set_current_buf(previous_buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  if not ok then
    error(result)
  end

  return result
end

local function with_stubbed_get_node(stub, fn)
  local original = vim.treesitter.get_node
  vim.treesitter.get_node = stub
  local ok, result = xpcall(fn, debug.traceback)
  vim.treesitter.get_node = original

  if not ok then
    error(result)
  end

  return result
end

M.tests[#M.tests + 1] = {
  name = "selects_standard_statement_nodes",
  fn = function()
    with_scratch_buffer({ "SELECT 1;" }, { 1, 0 }, function()
      local root = fake_node("program", { 0, 0, 0, 9 }, nil)
      local statement = fake_node("select_statement", { 0, 0, 0, 9 }, root)
      local identifier = fake_node("identifier", { 0, 7, 0, 8 }, statement)

      with_stubbed_get_node(function()
        return identifier
      end, function()
        assert_equal(select_sql_statement(), true, "expected selection to succeed")
        assert_equal(get_selected_text(), "SELECT 1;", "expected full statement to be selected")
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "falls_back_to_semicolon_delimited_statement_when_treesitter_only_returns_error_nodes",
  fn = function()
    with_scratch_buffer({ "GRANT SELECT ON users TO reader;", "SELECT 1;" }, { 1, 0 }, function()
      local root = fake_node("program", { 0, 0, 1, 9 }, nil)
      local error_node = fake_node("ERROR", { 0, 0, 0, 5 }, root)

      with_stubbed_get_node(function()
        return error_node
      end, function()
        assert_equal(select_sql_statement(), true, "expected selection to succeed")
        assert_equal(
          get_selected_text(),
          "GRANT SELECT ON users TO reader;",
          "expected semicolon fallback to ignore narrow error nodes"
        )
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "checks_previous_position_when_cursor_is_on_semicolon",
  fn = function()
    with_scratch_buffer({ "SELECT 1;" }, { 1, 8 }, function()
      local root = fake_node("program", { 0, 0, 0, 9 }, nil)
      local statement = fake_node("select_statement", { 0, 0, 0, 9 }, root)
      local identifier = fake_node("identifier", { 0, 7, 0, 8 }, statement)
      local punctuation = fake_node("punctuation", { 0, 8, 0, 9 }, statement)
      with_stubbed_get_node(function(args)
        if args and args.pos then
          return identifier
        end
        return punctuation
      end, function()
        assert_equal(select_sql_statement(), true, "expected selection to succeed")
        assert_equal(
          get_selected_text(),
          "SELECT 1;",
          "expected full statement to be selected when cursor is on the semicolon"
        )
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "falls_back_to_current_semicolon_delimited_statement_in_migration_style_sql_blocks",
  fn = function()
    with_scratch_buffer({
      "CREATE ROLE mats WITH LOGIN;",
      "",
      "-- 2. Connect privilege",
      "GRANT CONNECT ON DATABASE eldb TO mats;",
      "--",
      "-- 3. Read-only across public schema (adjust schema list if you also want others)",
      "GRANT USAGE ON SCHEMA public TO mats;",
      "GRANT SELECT ON ALL TABLES IN SCHEMA public TO mats;",
      "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO mats;",
      "",
      "-- Make future tables/sequences readable too",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO mats;",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO mats;",
      "",
      "-- 4. Write access on dso_tariffs only",
      "GRANT INSERT, UPDATE, DELETE ON public.dso_tariffs TO mats;",
      "GRANT USAGE, UPDATE ON SEQUENCE public.dso_tariffs_id_seq TO mats;",
      "",
      "GRANT INSERT, UPDATE, DELETE ON public.dso_tariff_components TO mats;",
    }, { 16, 0 }, function()
      local root = fake_node("program", { 0, 0, 18, 68 }, nil)
      local error_node = fake_node("ERROR", { 15, 0, 15, 5 }, root)

      with_stubbed_get_node(function()
        return error_node
      end, function()
        assert_equal(select_sql_statement(), true, "expected selection to succeed")
        assert_equal(
          get_selected_text(),
          "GRANT INSERT, UPDATE, DELETE ON public.dso_tariffs TO mats;",
          "expected only the current statement to be selected from the migration block"
        )
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "falls_back_to_blank_line_paragraph_selection_when_no_semicolon_exists",
  fn = function()
    with_scratch_buffer({ "", "GRANT SELECT ON users TO reader", "TO PUBLIC", "", "SELECT 1;" }, { 2, 0 }, function()
      with_stubbed_get_node(function()
        return nil
      end, function()
        assert_equal(select_sql_statement(), true, "expected paragraph fallback to succeed")
        assert_equal(
          get_selected_text(),
          "GRANT SELECT ON users TO reader\nTO PUBLIC",
          "expected paragraph fallback to select contiguous non-blank lines"
        )
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "returns_false_on_blank_lines_when_no_statement_is_found",
  fn = function()
    with_scratch_buffer({ "SELECT 1;", "", "GRANT SELECT ON users TO reader;" }, { 2, 0 }, function()
      with_stubbed_get_node(function()
        return nil
      end, function()
        assert_equal(select_sql_statement(), false, "expected blank-line fallback to fail cleanly")
      end)
    end)
  end,
}

M.tests[#M.tests + 1] = {
  name = "smoke_tests_real_sql_parser_when_available",
  fn = function()
    if not pcall(vim.treesitter.language.add, "sql") then
      vim.api.nvim_out_write("SKIP sql_selection.smoke_tests_real_sql_parser_when_available (sql parser unavailable)\n")
      return
    end

    with_scratch_buffer({ "GRANT SELECT ON users TO reader;" }, { 1, 0 }, function()
      vim.treesitter.start(0, "sql")
      local parser = vim.treesitter.get_parser(0, "sql")
      parser:parse()

      assert_equal(select_sql_statement(), true, "expected selection to succeed with real parser")
      assert_equal(
        get_selected_text(),
        "GRANT SELECT ON users TO reader;",
        "expected real parser smoke test to select the statement"
      )
    end)
  end,
}

return M
