require("setup-lazy")

vim.g.mapleader = ","
vim.g.coq_settings = {
	auto_start = "shut-up",
	keymap = {
		recommended = false,
		jump_to_mark = "<nop>",
		pre_select = true,
	},
}

require("plugins")

local builtin = require("telescope.builtin")

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
o.undofile = false
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
map("n", "<Leader>sv", ":source $MYVIMRC<CR>", { noremap = true })
map("n", "<localleader>b", ":NERDTreeToggle<CR>", { noremap = true })
map("n", "<localleader>,", ",", { noremap = true })
vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
vim.keymap.set("n", "<leader>fg", builtin.live_grep, {})
vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
vim.keymap.set("n", "<leader>fh", builtin.help_tags, {})

-- Visual mode remap for searching the selected text
map("v", "//", "y/\\V<C-R>=escape(@\",'/\\')<CR><CR>", { noremap = true })

-- Clipboard copy paste
map("", "<space>y", '"*y', { noremap = true })
map("", "<space>Y", '"*Y', { noremap = true })
map("", "<space>p", '"*p', { noremap = true })
map("", "<space>P", '"*P', { noremap = true })

-- Copilot, should override coq
map("i", "<Tab>", "pumvisible() ? '<C-N>' : copilot#Accept('<Tab>')", { noremap = true, expr = true, silent = true })
map(
	"i",
	"<CR>",
	"pumvisible() ? (complete_info().selected == -1 ? '<C-e><CR>' : '<C-y>') : '<CR>'",
	{ noremap = true, expr = true, silent = true }
)
map("i", "<Esc>", "pumvisible() ? '<C-e><Esc>' : '<Esc>'", { noremap = true, expr = true, silent = true })
map("i", "<C-c>", "pumvisible() ? '<C-e><C-c>' : '<C-c>'", { noremap = true, expr = true, silent = true })
map("i", "<BS>", "pumvisible() ? '<C-e><BS>' : '<BS>'", { noremap = true, expr = true, silent = true })

-- Looks
-- vim.g.molokai_original = 1
cmd("colorscheme molokai_old")

vim.api.nvim_create_user_command("Format", function()
	require("conform").format({ async = true, lsp_fallback = true })
end, {})
