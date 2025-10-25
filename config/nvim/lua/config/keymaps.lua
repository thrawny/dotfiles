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

-- Find files including gitignored (but exclude node_modules, .venv, .git)
vim.keymap.set("n", "<Leader>fF", function()
  require("snacks").picker.files({
    hidden = true,
    ignored = true,
    exclude = { "node_modules", ".venv", ".git", ".DS_Store" },
  })
end, { desc = "Find Files (all)" })

-- Grep including gitignored (but exclude node_modules, .venv, .git)
vim.keymap.set("n", "<Leader>sG", function()
  require("snacks").picker.grep({
    hidden = true,
    ignored = true,
    exclude = { "node_modules", ".venv", ".git", ".DS_Store" },
  })
end, { desc = "Grep (all)" })

-- Code action with Alt+Enter (in addition to default <leader>ca)
vim.keymap.set({ "n", "x" }, "<M-CR>", vim.lsp.buf.code_action, { desc = "Code Action" })
