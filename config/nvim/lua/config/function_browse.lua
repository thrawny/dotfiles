local M = {}

local function_foldexpr = "v:lua.vim.treesitter.foldexpr()"
local function_fold_highlight = "FunctionBrowseFolded"
local enabled = false
local saved_folded_highlights = {}
local supported_filetypes = {
  go = true,
  javascript = true,
  javascriptreact = true,
  lua = true,
  nix = true,
  python = true,
  rust = true,
  typescript = true,
  typescriptreact = true,
}

local function default_foldexpr(buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client:supports_method("textDocument/foldingRange") then
      return "v:lua.vim.lsp.foldexpr()"
    end
  end
  return "v:lua.LazyVim.treesitter.foldexpr()"
end

local function folded_highlight(value)
  for item in value:gmatch("[^,]+") do
    local target = item:match("^Folded:(.+)$")
    if target then
      return target
    end
  end
end

local function replace_folded_highlight(value, target)
  local items = {}
  for item in value:gmatch("[^,]+") do
    if not item:match("^Folded:") then
      items[#items + 1] = item
    end
  end
  if target then
    items[#items + 1] = "Folded:" .. target
  end
  return table.concat(items, ",")
end

local function apply_folded_highlight(win, should_fold)
  local value = vim.api.nvim_get_option_value("winhighlight", { win = win })
  if should_fold then
    if saved_folded_highlights[win] == nil then
      saved_folded_highlights[win] = folded_highlight(value) or false
    end
    value = replace_folded_highlight(value, function_fold_highlight)
  elseif saved_folded_highlights[win] ~= nil then
    local original = saved_folded_highlights[win]
    saved_folded_highlights[win] = nil
    value = replace_folded_highlight(value, original or nil)
  else
    return
  end
  vim.api.nvim_set_option_value("winhighlight", value, { win = win })
end

local function define_folded_highlight()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, function_fold_highlight, { bg = normal.bg })
end

local function apply_to_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local supported = vim.bo[buf].buftype == "" and supported_filetypes[vim.bo[buf].filetype]
  local should_fold = enabled and supported

  if should_fold then
    vim.api.nvim_set_option_value("foldmethod", "expr", { win = win })
    vim.api.nvim_set_option_value("foldexpr", function_foldexpr, { win = win })
  elseif supported and vim.api.nvim_get_option_value("foldexpr", { win = win }) == function_foldexpr then
    vim.api.nvim_set_option_value("foldexpr", default_foldexpr(buf), { win = win })
  end

  vim.api.nvim_set_option_value("foldlevel", should_fold and 0 or 99, { win = win })
  apply_folded_highlight(win, should_fold)
end

local function apply_to_all_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply_to_window(win)
  end
end

function M.toggle()
  enabled = not enabled
  apply_to_all_windows()
  vim.notify("Function browse mode " .. (enabled and "enabled" or "disabled"))
end

function M.is_enabled()
  return enabled
end

function M.setup()
  define_folded_highlight()
  vim.keymap.set("n", "<Leader>uo", M.toggle, { desc = "Toggle function browse mode" })

  vim.api.nvim_create_user_command("FunctionBrowseToggle", M.toggle, {
    desc = "Toggle function browse mode",
  })

  local group = vim.api.nvim_create_augroup("FunctionBrowseMode", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType", "LspAttach" }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      vim.schedule(function()
        apply_to_window(win)
      end)
    end,
    desc = "Apply function browse folds when changing buffers",
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = define_folded_highlight,
    desc = "Keep function browse folds on the normal background",
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      saved_folded_highlights[tonumber(args.match)] = nil
    end,
    desc = "Forget closed function browse windows",
  })
end

return M
