local M = {}

local function select_range(sr, sc, er, ec)
  vim.fn.setpos("'<", { 0, sr + 1, sc + 1, 0 })
  vim.fn.setpos("'>", { 0, er + 1, ec, 0 })
  vim.cmd("normal! gv")
  return true
end

local function select_paragraph()
  local line = vim.fn.line(".")
  if not vim.fn.getline(line):match("%S") then
    return false
  end

  local start_line = line
  local end_line = line
  local last_line = vim.fn.line("$")

  while start_line > 1 and vim.fn.getline(start_line - 1):match("%S") do
    start_line = start_line - 1
  end
  while end_line < last_line and vim.fn.getline(end_line + 1):match("%S") do
    end_line = end_line + 1
  end

  return select_range(start_line - 1, 0, end_line - 1, #vim.fn.getline(end_line))
end

local function select_statement_by_semicolon()
  local current_line = vim.fn.line(".")
  local current_col = vim.fn.col(".")
  local last_line = vim.fn.line("$")

  if not vim.fn.getline(current_line):match("%S") then
    return false
  end

  local start_line = 1
  local start_col = 1
  for line_nr = current_line, 1, -1 do
    local text = vim.fn.getline(line_nr)
    local limit = line_nr == current_line and (current_col - 1) or #text
    for col = limit, 1, -1 do
      if text:sub(col, col) == ";" then
        start_line = line_nr
        start_col = col + 1
        goto found_start
      end
    end
  end
  ::found_start::

  while start_line <= last_line do
    local text = vim.fn.getline(start_line)
    local segment = text:sub(start_col)
    local first_non_ws = segment:find("%S")

    if first_non_ws then
      local col = start_col + first_non_ws - 1
      if text:sub(col):match("^%-%-") then
        start_line = start_line + 1
        start_col = 1
      else
        start_col = col
        break
      end
    else
      start_line = start_line + 1
      start_col = 1
    end
  end

  if start_line > last_line then
    return false
  end

  for line_nr = current_line, last_line do
    local text = vim.fn.getline(line_nr)
    if line_nr > current_line and not text:match("%S") then
      return false
    end

    local first_col = line_nr == current_line and current_col or 1
    for col = first_col, #text do
      if text:sub(col, col) == ";" then
        return select_range(start_line - 1, start_col - 1, line_nr - 1, col)
      end
    end
  end

  return false
end

function M.select_sql_statement()
  local node = vim.treesitter.get_node()

  -- If on semicolon (outside the statement), get node before cursor
  local char = vim.fn.getline("."):sub(vim.fn.col("."), vim.fn.col("."))
  if char == ";" then
    local col = vim.fn.col(".")
    if col > 1 then
      node = vim.treesitter.get_node({ pos = { vim.fn.line(".") - 1, col - 2 } })
    end
  end

  local statement_node = nil
  while node do
    local type = node:type()
    if type:match("statement$") then
      statement_node = node
    end
    node = node:parent()
  end

  if statement_node then
    local sr, sc, er, ec = statement_node:range()
    return select_range(sr, sc, er, ec)
  end

  if select_statement_by_semicolon() then
    return true
  end

  return select_paragraph()
end

return M
