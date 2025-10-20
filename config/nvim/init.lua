require("setup-lazy")

vim.g.mapleader = ","
vim.g.copilot_no_tab_map = true

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
map("n", "<Leader>su", ":Lazy update<CR>", { noremap = true })
map("n", "<localleader>b", ":Neotree toggle<CR>", { noremap = true })
map("n", "<localleader>,", ",", { noremap = true })
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
vim.keymap.set("n", "gd", builtin.lsp_definitions, { desc = "Telescope go to definition" })
vim.keymap.set("n", "gi", builtin.lsp_implementations, { desc = "Telescope go to implementation" })
vim.keymap.set("n", "gf", builtin.lsp_references, { desc = "Telescope find references" })
vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })

-- Visual mode remap for searching the selected text
map("v", "//", "y/\\V<C-R>=escape(@\",'/\\')<CR><CR>", { noremap = true })

-- Clipboard copy paste
map("", "<space>y", '"*y', { noremap = true })
map("", "<space>Y", '"*Y', { noremap = true })
map("", "<space>p", '"*p', { noremap = true })
map("", "<space>P", '"*P', { noremap = true })

-- Copilot: Ctrl-Z accepts suggestion (macOS-compatible, avoids Alt/Meta key issues)
vim.keymap.set('i', '<C-Z>', 'copilot#Accept("\\<CR>")', {
	expr = true,
	silent = true,
	replace_keycodes = false,
	desc = "Copilot: Accept suggestion"
})

-- map("n", "<Leader>oq", ":ObsidianQuickSwitch<CR>", { noremap = true })

-- Looks
-- vim.g.molokai_original = 1
cmd("colorscheme molokai_old")

-- Enable true colors and transparent background
vim.opt.termguicolors = true
vim.cmd([[
  highlight Normal guibg=NONE ctermbg=NONE guifg=#E6E6E6 ctermfg=254
  highlight NonText guibg=NONE ctermbg=NONE guifg=#E6E6E6 ctermfg=254
  highlight LineNr guibg=NONE ctermbg=NONE guifg=#C0C0C0 ctermfg=250
  highlight SignColumn guibg=NONE ctermbg=NONE
  highlight EndOfBuffer guibg=NONE ctermbg=NONE guifg=#C0C0C0 ctermfg=250

  " Statusline/Powerline transparency
  highlight StatusLine guibg=NONE ctermbg=NONE
  highlight StatusLineNC guibg=NONE ctermbg=NONE
  highlight TabLine guibg=NONE ctermbg=NONE
  highlight TabLineFill guibg=NONE ctermbg=NONE
  highlight TabLineSel guibg=NONE ctermbg=NONE

  " Fix matching parentheses/brackets - use light gray background instead of black
  highlight MatchParen guibg=#444444 guifg=#FD971F gui=bold ctermbg=238 ctermfg=208
]])

vim.api.nvim_create_user_command("Format", function(args)
	local range = nil
	if args.count ~= -1 then
		local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
		range = {
			start = { args.line1, 0 },
			["end"] = { args.line2, end_line:len() },
		}
	end
	require("conform").format({ async = true, lsp_fallback = true, range = range })
end, { range = true })

vim.diagnostic.config({
	virtual_text = { spacing = 2, source = "if_many" },
	underline = true,
	signs = { severity_sort = true },
	update_in_insert = false,
	float = { border = "rounded", source = "if_many" },
})

local go_lsp_group = vim.api.nvim_create_augroup("golang_lsp_enhancements", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
	group = go_lsp_group,
	callback = function(args)
	local client = vim.lsp.get_client_by_id(args.data.client_id)
	local bufnr = args.buf
	if not client or vim.bo[bufnr].filetype ~= "go" then
		return
	end

	if client:supports_method("textDocument/codeAction") then
		vim.keymap.set("n", "<M-CR>", function()
			vim.lsp.buf.code_action({
					context = { only = { "source.organizeImports", "source.fixAll" } },
					apply = true,
				})
			end, { buffer = bufnr, desc = "Go: organize imports/fix" })
		end

	if client:supports_method("textDocument/signatureHelp") then
		vim.keymap.set("n", "gp", function()
			vim.lsp.buf.signature_help({ focusable = false })
		end, {
			buffer = bufnr,
			desc = "Go: signature help",
		})
	end

		if client:supports_method("textDocument/hover") then
			vim.keymap.set("n", "gh", function()
				vim.lsp.buf.hover({ focusable = false })
			end, { buffer = bufnr, desc = "Go: hover details" })
		end

		-- Note: completion is handled by blink.cmp, not native LSP completion
	end,
})
