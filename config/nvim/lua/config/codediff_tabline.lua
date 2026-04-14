-- Custom tabline that shows "Review" for codediff tabs
return function()
  local parts = {}
  for i = 1, vim.fn.tabpagenr("$") do
    local hl = i == vim.fn.tabpagenr() and "%#TabLineSel#" or "%#TabLine#"
    local label
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if ok and lifecycle.get_session(vim.api.nvim_list_tabpages()[i]) then
      label = " Review "
    else
      local bufnr = vim.fn.tabpagebuflist(i)[vim.fn.tabpagewinnr(i)]
      local name = vim.fn.fnamemodify(vim.fn.bufname(bufnr), ":t")
      if name == "" then
        name = "[No Name]"
      end
      label = " " .. name .. " "
    end
    table.insert(parts, hl .. "%" .. i .. "T" .. label)
  end
  table.insert(parts, "%#TabLineFill#")
  return table.concat(parts)
end
