-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle between current and alternate buffer (and center cursor)
vim.keymap.set("n", "<Leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

-- Jump to previous/next location (across buffers, like VSCode)
vim.keymap.set("n", "[e", "<C-o>", { desc = "Previous jump location", silent = true })
vim.keymap.set("n", "]e", "<C-i>", { desc = "Next jump location", silent = true })
