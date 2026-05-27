-- Custom tabline that shows "Review" for codediff tabs and hides inactive dashboard tabs.
local function tab_bufnr(tabnr)
  return vim.fn.tabpagebuflist(tabnr)[vim.fn.tabpagewinnr(tabnr)]
end

local function is_codediff_tab(tabpage)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  return ok and lifecycle.get_session(tabpage) ~= nil
end

local function is_dashboard_tab(tabnr)
  local bufnr = tab_bufnr(tabnr)
  local name = vim.fn.bufname(bufnr)
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  return name == "" and ft == "snacks_dashboard"
end

return function()
  local parts = {}
  local tabs = vim.api.nvim_list_tabpages()
  local current = vim.fn.tabpagenr()

  for i = 1, #tabs do
    -- Keep the splash tab as a real return target, but don't show it while
    -- another tab (for example Review) is active.
    if not (i ~= current and is_dashboard_tab(i)) then
      local hl = i == current and "%#TabLineSel#" or "%#TabLine#"
      local label
      if is_codediff_tab(tabs[i]) then
        label = " Review "
      else
        local bufnr = tab_bufnr(i)
        local name = vim.fn.fnamemodify(vim.fn.bufname(bufnr), ":t")
        if name == "" then
          name = "[No Name]"
        end
        label = " " .. name .. " "
      end
      table.insert(parts, hl .. "%" .. i .. "T" .. label)
    end
  end

  table.insert(parts, "%#TabLineFill#")
  return table.concat(parts)
end
