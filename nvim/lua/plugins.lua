local notesPath = vim.fn.expand("~") .. "/work-notes"

require("lazy").setup({
	"tpope/vim-surround",
	{
		"christoomey/vim-tmux-navigator",
		cmd = {
			"TmuxNavigateLeft",
			"TmuxNavigateDown",
			"TmuxNavigateUp",
			"TmuxNavigateRight",
			"TmuxNavigatePrevious",
		},
		keys = {
			{ "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>" },
			{ "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>" },
			{ "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>" },
			{ "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>" },
			{ "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>" },
		},
		-- "williamboman/mason.nvim",
		-- "williamboman/mason-lspconfig.nvim",
		-- "nvimtools/none-ls.nvim",
		-- {
		-- 	"stevearc/conform.nvim",
		-- 	event = { "BufWritePre" },
		-- 	cmd = { "ConformInfo" },
		-- 	keys = {
		-- 		{
		-- 			-- Customize or remove this keymap to your liking
		-- 			"<leader>f",
		-- 			function()
		-- 				require("conform").format({ async = true, lsp_fallback = true })
		-- 			end,
		-- 			mode = "",
		-- 			desc = "Format buffer",
		-- 		},
		-- 	},
		-- 	-- Everything in opts will be passed to setup()
		-- 	opts = {
		-- 		-- Define your formatters
		-- 		formatters_by_ft = {
		-- 			lua = { "stylua" },
		-- 			python = { "isort", "black" },
		-- 			javascript = { { "prettierd", "prettier" } },
		-- 			yaml = { { "prettierd", "prettier" } },
		-- 			json = { { "prettierd", "prettier" } },
		-- 			markdown = { { "prettierd", "prettier" } },
		-- 			xml = { "xmlformat" },
		-- 		},
		-- 		-- Set up format-on-save
		-- 		format_on_save = { timeout_ms = 500, lsp_fallback = true },
		-- 		-- Customize formatters
		-- 		formatters = {
		-- 			shfmt = {
		-- 				prepend_args = { "-i", "2" },
		-- 			},
		-- 		},
		-- 	},
		-- 	init = function()
		-- 		-- If you want the formatexpr, here is the place to set it
		-- 		vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
		-- 	end,
		-- },
		-- {
		-- 	"nvim-telescope/telescope.nvim",
		-- 	tag = "0.1.6",
		-- 	dependencies = { "nvim-lua/plenary.nvim" },
		-- },
		-- {
		-- 	"nvim-treesitter/nvim-treesitter",
		-- 	build = ":TSUpdate",
		-- },
		{
			"numToStr/Comment.nvim",
			opts = {
				-- add any options here
			},
			lazy = false,
		},
		-- "mfussenegger/nvim-ansible",
		-- {
		-- 	"stevearc/oil.nvim",
		-- 	opts = {},
		-- 	-- Optional dependencies
		-- 	dependencies = { "nvim-tree/nvim-web-devicons" },
		-- },
		-- "neovim/nvim-lspconfig",
		-- {
		-- 	"ms-jpq/coq_nvim",
		-- 	branch = "coq",
		-- },
		-- {
		-- 	"ms-jpq/coq.artifacts",
		-- 	branch = "artifacts",
		-- },
		-- { "folke/neodev.nvim", opts = {} },
		-- {
		-- 	"jay-babu/mason-null-ls.nvim",
		-- 	event = { "BufReadPre", "BufNewFile" },
		-- 	dependencies = {
		-- 		"williamboman/mason.nvim",
		-- 		"nvimtools/none-ls.nvim",
		-- 	},
		-- },
		{
			"nvim-lualine/lualine.nvim",
			dependencies = { "nvim-tree/nvim-web-devicons" },
		},
		"UtkarshVerma/molokai.nvim",
		-- {
		-- 	"epwalsh/obsidian.nvim",
		-- 	version = "*", -- recommended, use latest release instead of latest commit
		-- 	lazy = true,
		-- 	ft = "markdown",
		-- 	-- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
		-- 	event = {
		-- 		-- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
		-- 		"BufReadPre "
		-- 			.. notesPath
		-- 			.. "/**.md",
		-- 		"BufNewFile " .. notesPath .. "/**.md",
		-- 	},
		-- 	dependencies = {
		-- 		-- Required.
		-- 		"nvim-lua/plenary.nvim",

		-- 		-- see below for full list of optional dependencies 👇
		-- 	},
		-- },
	},
})

-- local coq = require("coq")
-- local lsp = require("lspconfig")

-- require("neodev").setup()
-- require("mason").setup()
-- require("mason-lspconfig").setup({
-- 	ensure_installed = { "lua_ls" },
-- 	automatic_installation = true,
-- })
-- require("mason-null-ls").setup({
-- 	ensure_installed = { "stylua", "xmlformatter" },
-- 	automatic_installation = true,
-- })
require("lualine").setup({
	options = {
		theme = "molokai",
	},
})
-- require("obsidian").setup({
--
-- 	workspaces = {
-- 		{
-- 			name = "work_notes",
-- 			path = notesPath,
-- 		},
-- 	},
--
-- 	ui = {
-- 		enable = false,
-- 	},
-- })

-- lsp.lua_ls.setup(coq.lsp_ensure_capabilities({
-- 	on_init = function(client)
-- 		local path = client.workspace_folders[1].name
-- 		if vim.loop.fs_stat(path .. "/.luarc.json") or vim.loop.fs_stat(path .. "/.luarc.jsonc") then
-- 			return
-- 		end

-- 		client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
-- 			runtime = {
-- 				-- Tell the language server which version of Lua you're using
-- 				-- (most likely LuaJIT in the case of Neovim)
-- 				version = "LuaJIT",
-- 			},
-- 			-- Make the server aware of Neovim runtime files
-- 			workspace = {
-- 				checkThirdParty = false,
-- 				library = {
-- 					vim.env.VIMRUNTIME,
-- 					-- Depending on the usage, you might want to add additional paths here.
-- 					-- "${3rd}/luv/library"
-- 					-- "${3rd}/busted/library",
-- 				},
-- 				-- or pull in all of 'runtimepath'. NOTE: this is a lot slower
-- 				-- library = vim.api.nvim_get_runtime_file("", true)
-- 			},
-- 		})
-- 	end,
-- 	settings = {
-- 		Lua = {},
-- 	},
-- }))

-- require("nvim-treesitter.configs").setup({
-- 	ensure_installed = "all",

-- 	auto_install = true,

-- 	highlight = {
-- 		enable = true,
-- 	},
-- })

-- require("conform").formatters.injected = {
-- 	-- Set the options field
-- 	options = {
-- 		-- Set individual option values
-- 		ignore_errors = true,
-- 		lang_to_formatters = {
-- 			json = { { "prettierd", "prettier" } },
-- 			xml = { "xmlformat" },
-- 		},
-- 	},
-- }
