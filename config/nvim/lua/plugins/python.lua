local python_project = require("config.python_project")

return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters = opts.linters or {}
      opts.linters.mypy = python_project.mypy_linter

      -- mypy is too slow for LazyVim's BufReadPost/InsertLeave triggers, so it
      -- runs on save only, and only where the project configures it.
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("dotfiles_mypy", { clear = true }),
        pattern = "*.py",
        callback = function(args)
          local checker = python_project.type_checker(vim.api.nvim_buf_get_name(args.buf))
          if checker and checker.name == "mypy" and checker.cmd then
            require("lint").try_lint("mypy")
          end
        end,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          -- Pre-seeded so before_init can mutate it in place; the client copies
          -- this table on creation, so reassigning config.settings there would
          -- never reach the server.
          settings = { basedpyright = { analysis = {} } },
          -- Keep basedpyright for completion, hover and navigation everywhere,
          -- but leave type diagnostics to whatever the project configures.
          before_init = function(_, config)
            local checker = python_project.type_checker(config.root_dir or vim.uv.cwd())
            if checker and checker.name == "basedpyright" then
              return
            end
            local analysis = vim.tbl_get(config, "settings", "basedpyright", "analysis")
            if analysis then
              analysis.typeCheckingMode = "off"
            end
          end,
        },
      },
    },
  },
}
