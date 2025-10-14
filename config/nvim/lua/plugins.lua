local notesPath = vim.fn.expand("~") .. "/work-notes"

-- Detect light mode: disable heavy plugins in devpod or when explicitly requested
local nvim_light = vim.env.DEVPOD or vim.env.NVIM_LIGHT

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
					-- Customize or remove this keymap to your liking
					"<leader>f",
					function()
						require("conform").format({ async = true, lsp_fallback = true })
					end,
					mode = "",
					desc = "Format buffer",
				},
			},
			-- Everything in opts will be passed to setup()
			opts = {
				-- Define your formatters
				formatters_by_ft = {
					lua = { "stylua" },
					python = { "ruff_format", "ruff_organize_imports" },
					javascript = { { "prettierd", "prettier" } },
					yaml = { { "prettierd", "prettier" } },
					json = { { "prettierd", "prettier" } },
					markdown = { { "prettierd", "prettier" } },
					xml = { "xmlformat" },
				},
				-- Set up format-on-save
				format_on_save = { timeout_ms = 500, lsp_fallback = true },
				-- Customize formatters
				formatters = {
					shfmt = {
						prepend_args = { "-i", "2" },
					},
				},
			},
			init = function()
				-- If you want the formatexpr, here is the place to set it
				vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
			end,
		},
		{
			"nvim-telescope/telescope.nvim",
			tag = "0.1.8",
			dependencies = { "nvim-lua/plenary.nvim" },
		},
		not nvim_light and {
			"nvim-treesitter/nvim-treesitter",
			build = ":TSUpdate",
		} or nil,
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
		not nvim_light and {
				"williamboman/mason.nvim",
				opts = {},
			} or nil,
		not nvim_light and {
			"williamboman/mason-lspconfig.nvim",
			dependencies = { "williamboman/mason.nvim" },
			opts = {
				ensure_installed = { "lua_ls", "gopls" },
				automatic_installation = true,
			},
		} or nil,
		not nvim_light and "neovim/nvim-lspconfig" or nil,
		not nvim_light and {
			"ms-jpq/coq_nvim",
			branch = "coq",
		} or nil,
		not nvim_light and {
			"ms-jpq/coq.artifacts",
			branch = "artifacts",
		} or nil,
		not nvim_light and { "folke/neodev.nvim", opts = {} } or nil,
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

if not nvim_light then
	local coq = require("coq")
	local lsp = require("lspconfig")

	require("neodev").setup()
	require("mason").setup()
	require("mason-lspconfig").setup({
		ensure_installed = { "lua_ls", "gopls" },
		automatic_installation = true,
	})

	-- Lua LSP with neodev support
	lsp.lua_ls.setup(coq.lsp_ensure_capabilities({
		on_init = function(client)
			local path = client.workspace_folders[1].name
			if vim.loop.fs_stat(path .. "/.luarc.json") or vim.loop.fs_stat(path .. "/.luarc.jsonc") then
				return
			end

			client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
				runtime = {
					version = "LuaJIT",
				},
				workspace = {
					checkThirdParty = false,
					library = {
						vim.env.VIMRUNTIME,
					},
				},
			})
		end,
		settings = {
			Lua = {},
		},
	}))

	-- Go LSP
	lsp.gopls.setup(coq.lsp_ensure_capabilities({}))
end
-- require("mason-null-ls").setup({
-- 	ensure_installed = { "stylua", "xmlformatter" },
-- 	automatic_installation = true,
-- })

-- Lualine statusline (skip in light mode to avoid icon dependency errors)
if not nvim_light then
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

if not nvim_light then
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
