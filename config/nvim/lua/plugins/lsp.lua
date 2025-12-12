return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      -- Prevent LSP from attaching to non-file URI schemes (diffview://, fugitive://, etc.)
      -- This avoids gopls "DocumentURI scheme is not 'file'" errors
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufname = vim.api.nvim_buf_get_name(args.buf)
          if bufname:match("^%a+://") then
            vim.schedule(function()
              vim.lsp.buf_detach_client(args.buf, args.data.client_id)
            end)
          end
        end,
      })

      -- Disable semantic token highlighting for all LSP servers
      -- Instead of removing the capability (which breaks some LSP features),
      -- we clear all semantic highlight groups so they have no visual effect
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          -- Clear all @lsp.type.* and @lsp.mod.* highlight groups
          for _, group in ipairs(vim.fn.getcompletion("@lsp", "highlight")) do
            vim.api.nvim_set_hl(0, group, {})
          end
        end,
      })

      -- Also disable on LspAttach to catch any dynamically created highlights
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function()
          vim.schedule(function()
            for _, group in ipairs(vim.fn.getcompletion("@lsp", "highlight")) do
              vim.api.nvim_set_hl(0, group, {})
            end
          end)
        end,
      })
    end,
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        -- Disable <leader>co (organize imports) in diffview buffers so it doesn't
        -- conflict with diffview's conflict_choose("ours") binding
        ["*"] = {
          keys = {
            {
              "<leader>co",
              LazyVim.lsp.action["source.organizeImports"],
              desc = "Organize Imports",
              has = "codeAction",
              enabled = function()
                return not vim.api.nvim_buf_get_name(0):match("^diffview://")
              end,
            },
          },
        },
        -- Use system-installed basedpyright (via uv in dotfiles venv)
        basedpyright = {
          mason = false,
        },
        -- Use system-installed ruff (via uv in dotfiles venv)
        ruff = {
          mason = false,
        },
      },
    },
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      -- Prevent mason-lspconfig from auto-enabling Python tools
      automatic_enable = {
        exclude = { "basedpyright", "ruff" },
      },
    },
  },
}
