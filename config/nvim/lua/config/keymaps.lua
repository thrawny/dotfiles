-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle between current and alternate buffer (and center cursor)
vim.keymap.set("n", "<Leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

-- Jump to previous/next location (across buffers, like VSCode)
vim.keymap.set("n", "[e", "<C-o>", { desc = "Previous jump location", silent = true })
vim.keymap.set("n", "]e", "<C-i>", { desc = "Next jump location", silent = true })

-- Clipboard copy/paste (works in normal, visual, and operator-pending modes)
vim.keymap.set({ "n", "v", "o" }, "<space>y", '"*y', { desc = "Yank to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>Y", '"*Y', { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>p", '"*p', { desc = "Paste from system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>P", '"*P', { desc = "Paste before from system clipboard" })
