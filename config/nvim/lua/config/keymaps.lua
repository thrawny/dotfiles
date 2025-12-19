-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle between current and alternate buffer (and center cursor)
vim.keymap.set("n", "<Leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

-- Jump to previous/next location (across buffers, like VSCode)
vim.keymap.set("n", "[e", "<C-o>", { desc = "Previous jump location", silent = true })
vim.keymap.set("n", "]e", "<C-i>", { desc = "Next jump location", silent = true })

-- Clipboard copy/paste (works in normal, visual, and operator-pending modes)
vim.keymap.set({ "n", "v", "o" }, "<space>y", '"+y', { desc = "Yank to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>Y", '"+Y', { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>p", '"+p', { desc = "Paste from system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>P", '"+P', { desc = "Paste before from system clipboard" })

-- Keep cursor centered during search navigation
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })

-- Clear search highlighting
vim.keymap.set("n", "<Leader>o", ":noh<CR>", { desc = "Clear search highlighting", silent = true })

-- Terminal mode: Ctrl+A goes to start of line (shell behavior)
vim.keymap.set("t", "<C-a>", "<Home>", { desc = "Go to start of line in terminal" })

-- Terminal toggle with Alt+; is defined in lua/plugins/ui.lua (snacks.nvim keys spec)

-- Copy file reference to clipboard for Claude Code
vim.keymap.set("n", "<Leader>at", function()
  local file = vim.fn.expand("%:.")
  local line = vim.fn.line(".")
  local ref = "@" .. file .. " (line " .. line .. ")"
  vim.fn.setreg("+", ref)
  vim.notify("Copied: " .. ref)
end, { desc = "Copy @file (line) to clipboard" })

vim.keymap.set("v", "<Leader>at", function()
  local file = vim.fn.expand("%:.")
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local ref
  if start_line == end_line then
    ref = "@" .. file .. " (line " .. start_line .. ")"
  else
    ref = "@" .. file .. " (lines " .. start_line .. "-" .. end_line .. ")"
  end
  vim.fn.setreg("+", ref)
  vim.notify("Copied: " .. ref)
end, { desc = "Copy @file (lines) to clipboard" })

vim.keymap.set("n", "<Tab>", require("violet").accept_prediction_expr, { expr = true, silent = true })
