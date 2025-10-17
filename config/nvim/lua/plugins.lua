-- Detect light mode: disable heavy plugins in devpod or when explicitly requested
local nvim_light = vim.env.DEVPOD or vim.env.NVIM_LIGHT

local function configure_heavy_lsp()
	if nvim_light then
		return
	end

	local coq = require("coq")

	require("mason").setup()

	-- Lua LSP using new vim.lsp.config API
	vim.lsp.config("lua_ls", {
		cmd = { "lua-language-server" },
		filetypes = { "lua" },
		root_markers = {
			".luarc.json",
			".luarc.jsonc",
			".luacheckrc",
			".stylua.toml",
			"stylua.toml",
			"selene.toml",
			"selene.yml",
			".git",
		},
		single_file_support = true,
		capabilities = coq.lsp_ensure_capabilities(vim.lsp.protocol.make_client_capabilities()),
		settings = {
			Lua = {
				runtime = {
					version = "LuaJIT",
				},
				workspace = {
					checkThirdParty = false,
					library = {
						vim.env.VIMRUNTIME,
					},
				},
			},
		},
	})
	vim.lsp.enable("lua_ls")

	-- Go LSP using new vim.lsp.config API
	vim.lsp.config("gopls", {
		cmd = { "gopls" },
		filetypes = { "go", "gomod", "gowork", "gotmpl" },
		root_markers = { "go.work", "go.mod", ".git" },
		single_file_support = true,
		capabilities = coq.lsp_ensure_capabilities(vim.lsp.protocol.make_client_capabilities()),
		settings = {
			gopls = {
				["ui.diagnostic.staticcheck"] = true,
				analyses = {
					unusedparams = true,
					unusedwrite = true,
				},
			},
		},
	})
	vim.lsp.enable("gopls")

	-- Nix LSP using new vim.lsp.config API
	vim.lsp.config("nixd", {
		cmd = { "nixd" },
		filetypes = { "nix" },
		root_markers = { "flake.nix", "default.nix", "shell.nix", ".git" },
		single_file_support = true,
		capabilities = coq.lsp_ensure_capabilities(vim.lsp.protocol.make_client_capabilities()),
	})
	vim.lsp.enable("nixd")
end

local function configure_lualine()
	if nvim_light then
		return
	end

	require("lualine").setup({
		options = {
			theme = "auto",
			section_separators = "",
			component_separators = "",
			globalstatus = true,
			-- Molokai theme colors with transparent backgrounds
			theme = {
				normal = {
					a = { bg = "NONE", fg = "#66d9ef", gui = "bold" }, -- cyan
					b = { bg = "NONE", fg = "#f92672" }, -- pink
					c = { bg = "NONE", fg = "#ef5939" }, -- orange
				},
				insert = {
					a = { bg = "NONE", fg = "#a6e22e", gui = "bold" }, -- green
					b = { bg = "NONE", fg = "#f92672" }, -- pink
					c = { bg = "NONE", fg = "#ef5939" }, -- orange
				},
				visual = {
					a = { bg = "NONE", fg = "#e6db74", gui = "bold" }, -- yellow
					b = { bg = "NONE", fg = "#f92672" }, -- pink
					c = { bg = "NONE", fg = "#ef5939" }, -- orange
				},
				replace = {
					a = { bg = "NONE", fg = "#ff0000", gui = "bold" }, -- red
					b = { bg = "NONE", fg = "#f92672" }, -- pink
					c = { bg = "NONE", fg = "#ef5939" }, -- orange
				},
				command = {
					a = { bg = "NONE", fg = "#66d9ef", gui = "bold" }, -- cyan
					b = { bg = "NONE", fg = "#f92672" }, -- pink
					c = { bg = "NONE", fg = "#ef5939" }, -- orange
				},
				inactive = {
					a = { bg = "NONE", fg = "#f92672", gui = "bold" }, -- pink
					b = { bg = "NONE", fg = "#f8f8f2" }, -- white
					c = { bg = "NONE", fg = "#808080" }, -- gray
				},
			},
		},
	})
end

local function configure_treesitter()
	if nvim_light then
		return
	end

	require("nvim-treesitter.configs").setup({
		ensure_installed = {
			"markdown",
			"markdown_inline",
			"python",
			"lua",
			"bash",
			"javascript",
			"typescript",
			"go",
			"yaml",
			"json",
		},

		auto_install = true,

		highlight = {
			enable = true,
		},
	})
end

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
		{
			"stevearc/conform.nvim",
			event = { "BufWritePre" },
			cmd = { "ConformInfo" },
			keys = {
				{
					"<leader>f",
					function()
						require("conform").format({ async = true, lsp_fallback = true })
					end,
					mode = "",
					desc = "Format buffer",
				},
			},
			opts = {
				formatters_by_ft = {
					go = { "golangci-lint" },
					lua = { "stylua" },
					python = { "ruff_format", "ruff_organize_imports" },
					javascript = { "prettierd", "prettier", stop_after_first = true },
					yaml = { "prettierd", "prettier", stop_after_first = true },
					json = { "prettierd", "prettier", stop_after_first = true },
					markdown = { "prettierd", "prettier", stop_after_first = true },
					nix = { "nixfmt" },
					xml = { "xmlformat" },
				},
				format_on_save = { timeout_ms = 500, lsp_fallback = true },
				formatters = {
					nixfmt = {
						command = "nixfmt",
						stdin = true,
					},
					tombi = {
						command = "uvx",
						args = { "tombi", "format", "$FILENAME" },
						stdin = false,
					},
					shfmt = {
						prepend_args = { "-i", "2" },
					},
				},
			},
			init = function()
				vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
			end,
		},
		{
			"nvim-telescope/telescope.nvim",
			tag = "master",
			dependencies = { "nvim-lua/plenary.nvim" },
		},
		{
			"nvim-treesitter/nvim-treesitter",
			cond = not nvim_light,
			build = ":TSUpdate",
		},
		{
			"numToStr/Comment.nvim",
			opts = {},
			lazy = false,
		},
		{
			"williamboman/mason.nvim",
			cond = not nvim_light,
			opts = {},
		},
		{
			"ms-jpq/coq_nvim",
			cond = not nvim_light,
			branch = "coq",
		},
		{
			"ms-jpq/coq.artifacts",
			cond = not nvim_light,
			branch = "artifacts",
		},
		{
			"nvim-lualine/lualine.nvim",
			dependencies = { "nvim-tree/nvim-web-devicons" },
		},
		"UtkarshVerma/molokai.nvim",
		{
			"nvim-neo-tree/neo-tree.nvim",
			branch = "v3.x",
			dependencies = {
				"nvim-lua/plenary.nvim",
				"nvim-tree/nvim-web-devicons",
				"MunifTanjim/nui.nvim",
			},
			lazy = false,
			opts = {
				close_if_last_window = false,
				popup_border_style = "rounded",
				enable_git_status = true,
				enable_diagnostics = true,
				default_component_configs = {
					indent = {
						indent_size = 2,
						padding = 1,
						with_markers = true,
						indent_marker = "│",
						last_indent_marker = "└",
					},
					icon = {
						folder_closed = "",
						folder_open = "",
						folder_empty = "󰜌",
						default = "*",
					},
					git_status = {
						symbols = {
							added = "",
							modified = "",
							deleted = "✖",
							renamed = "󰁕",
							untracked = "",
							ignored = "",
							unstaged = "󰄱",
							staged = "",
							conflict = "",
						},
					},
				},
				window = {
					position = "left",
					width = 30,
					mappings = {
						["<space>"] = "toggle_node",
						["<cr>"] = "open",
						["o"] = "open",
						["l"] = "open",
						["h"] = "close_node",
						["v"] = "open_vsplit",
						["s"] = "open_split",
						["t"] = "open_tabnew",
						["C"] = "close_node",
						["z"] = "close_all_nodes",
						["R"] = "refresh",
						["a"] = "add",
						["d"] = "delete",
						["r"] = "rename",
						["y"] = "copy_to_clipboard",
						["x"] = "cut_to_clipboard",
						["p"] = "paste_from_clipboard",
						["q"] = "close_window",
						["O"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "O" } },
						["Oc"] = "order_by_created",
						["Od"] = "order_by_diagnostics",
						["Om"] = "order_by_modified",
						["On"] = "order_by_name",
						["Os"] = "order_by_size",
						["Ot"] = "order_by_type",
					},
				},
				filesystem = {
					filtered_items = {
						hide_dotfiles = false,
						hide_gitignored = false,
					},
					follow_current_file = {
						enabled = true,
					},
				},
			},
		},
		{
			"folke/which-key.nvim",
			event = "VeryLazy",
			opts = {
				preset = "classic",
				delay = 200,
				plugins = {
					marks = true,
					registers = true,
					spelling = {
						enabled = true,
						suggestions = 20,
					},
					presets = {
						operators = true,
						motions = true,
						text_objects = true,
						windows = true,
						nav = true,
						z = true,
						g = true,
					},
				},
				win = {
					border = "rounded",
					padding = { 1, 2 },
				},
			},
		},
	},
})

configure_heavy_lsp()

-- Lualine statusline (skip in light mode to avoid icon dependency errors)
configure_lualine()

configure_treesitter()
