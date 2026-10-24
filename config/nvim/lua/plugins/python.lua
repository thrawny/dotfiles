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
        ty = {
          mason = false,
          cmd = { "ty", "server" },
          root_markers = {
            { "ty.toml", "pyproject.toml", "mypy.ini", ".mypy.ini", "setup.py", "setup.cfg", "requirements.txt" },
            ".git",
          },
          init_options = { experimental = { useUv = "on" } },
          -- Preserve project-selected diagnostics while using ty for language
          -- services everywhere, including projects checked by mypy on save.
          settings = { ty = { diagnosticMode = "off" } },
          before_init = function(_, config)
            local checker = python_project.type_checker(config.root_dir or vim.api.nvim_buf_get_name(0))
            if checker and checker.name == "ty" then
              config.settings.ty.diagnosticMode = "openFilesOnly"
            end
          end,
        },
      },
    },
  },
}
