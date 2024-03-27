require("setup-lazy")

vim.g.mapleader = ","

require("plugins")

local set = vim.opt
local cmd = vim.cmd
local o = vim.o
local map = vim.api.nvim_set_keymap

o.encoding = "utf-8"
o.backspace = "indent,eol,start"
o.ruler = true
o.expandtab = true
o.shiftwidth = 2
o.softtabstop = 2
o.tabstop = 4
o.number = true
o.numberwidth = 3
o.hidden = true
o.tw = 80
o.mouse = "a"
o.timeoutlen = 1000
o.ttimeoutlen = 10
o.backupdir = vim.fn.expand("~/.config/nvim/backup//")
o.directory = vim.fn.expand("~/.config/nvim/swap//")
o.undodir = vim.fn.expand("~/.config/nvim/undo//")
o.backup = true
o.swapfile = false
o.autoread = true
o.textwidth = 0
o.wrapmargin = 0

-- Searching
o.incsearch = true
o.hlsearch = true
-- To turn off highlighting use :nohl in command mode
o.ignorecase = true
o.smartcase = true

-- Insert mode mappings
map("i", "{<CR>", "{<CR>}<Esc>ko", { noremap = true })
map("i", "({<CR>", "({<CR>});<Esc>ko", { noremap = true })

-- Normal mode mappings for easier moving between buffers
map("n", "<Leader>n", "<esc>:bp<CR>", { noremap = true })
map("n", "<Leader>m", "<esc>:bn<CR>", { noremap = true })

-- Visual mode mapping for sorting
map("v", "<Leader>s", ":sort<CR>", { noremap = true })

-- Normal mode mappings
map("n", "<Leader>lc", ":lclose<CR>", { noremap = true })
map("n", "<Leader>o", ":noh<ESC>", { noremap = true, silent = true })
map("n", "Y", "y$", { noremap = true })
map("n", "<C-d>", "<C-d>zz", { noremap = true })
map("n", "<C-u>", "<C-u>zz", { noremap = true })
map("n", "n", "nzzzv", { noremap = true })
map("n", "N", "Nzzzv", { noremap = true })
map("n", "<Leader>,", "<C-^>zz", { noremap = true })
map("n", "<Leader>v", ":e $MYVIMRC<CR>", { noremap = true })
map("n", "<Leader>z", ":e ~/.zshrc<CR>", { noremap = true })
map("n", "<Leader>i", ":e ~/dotfiles/linux/i3/config<CR>", { noremap = true })
map("n", "<Leader>tm", ":e ~/.tmux.conf<CR>", { noremap = true })
map("n", "<Leader>sv", ":source $MYVIMRC<CR>", { noremap = true })
map("n", "<localleader>b", ":NERDTreeToggle<CR>", { noremap = true })
map("n", "<localleader>,", ",", { noremap = true })

-- Expression mapping (might need adjustment for Lua)
-- map('n', 'gp', '`[' .. vim.fn.strpart(vim.fn.getregtype(), 0, 1) .. '`]', {noremap = true, expr = true})

-- Visual mode remap for searching the selected text
map("v", "//", "y/\\V<C-R>=escape(@\",'/\\')<CR><CR>", { noremap = true })

-- Clipboard copy paste
map("", "<space>y", '"*y', { noremap = true })
map("", "<space>Y", '"*Y', { noremap = true })
map("", "<space>p", '"*p', { noremap = true })
map("", "<space>P", '"*P', { noremap = true })

-- Looks
vim.g.molokai_original = 1
cmd("colorscheme molokai")
