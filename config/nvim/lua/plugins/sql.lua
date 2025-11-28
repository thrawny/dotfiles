-- Select SQL statement at cursor using treesitter
local function select_sql_statement()
  local node = vim.treesitter.get_node()
  if not node then
    return false
  end
  -- If on semicolon (outside the statement), get node before cursor
  local char = vim.fn.getline("."):sub(vim.fn.col("."), vim.fn.col("."))
  if char == ";" then
    local col = vim.fn.col(".")
    if col > 1 then
      node = vim.treesitter.get_node({ pos = { vim.fn.line(".") - 1, col - 2 } })
    end
  end
  if not node then
    return false
  end
  -- Walk up to find outermost statement node
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
    vim.fn.setpos("'<", { 0, sr + 1, sc + 1, 0 })
    vim.fn.setpos("'>", { 0, er + 1, ec, 0 })
    vim.cmd("normal! gv")
    return true
  end
  return false
end

return {
  {
    "kristijanhusak/vim-dadbod-ui",
    keys = {
      {
        ",r",
        select_sql_statement,
        desc = "Select query at cursor",
        ft = "sql",
      },
      {
        ",S",
        function()
          if select_sql_statement() then
            vim.cmd("normal! \27") -- ESC to exit visual
            vim.cmd("'<,'>DB")
          end
        end,
        desc = "Execute query at cursor",
        ft = "sql",
      },
    },
  },
  {
    "folke/edgy.nvim",
    opts = function(_, opts)
      -- Move DBUI from right sidebar to left sidebar
      opts.right = opts.right or {}
      opts.left = opts.left or {}

      -- Find the dbui entry in opts.right
      local dbui_index = nil
      for i, view in ipairs(opts.right) do
        if view.ft == "dbui" then
          dbui_index = i
          break
        end
      end

      -- If found, remove from right and add to left
      if dbui_index then
        local dbui_view = table.remove(opts.right, dbui_index)
        dbui_view.width = 0.3
        table.insert(opts.left, dbui_view)
      end

      -- Find and modify the existing dbout entry from SQL extra
      opts.bottom = opts.bottom or {}
      for _, view in ipairs(opts.bottom) do
        if view.ft == "dbout" then
          view.size = { height = 0.3 }
          break
        end
      end
    end,
  },
}
