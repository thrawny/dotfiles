-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Set leader key to comma
vim.g.mapleader = ","
vim.g.maplocalleader = ","

-- Use basedpyright as Python LSP
vim.g.lazyvim_python_lsp = "basedpyright"

-- Disable Copilot integration with completion menu to enable automatic ghost text
vim.g.ai_cmp = false

-- Auto-reload files when changed externally
vim.opt.autoread = true
