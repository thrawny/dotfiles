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

      -- Work around noisy taplo shutdown errors on quit.
      -- taplo may respond with "server is shutting down" after Neovim already
      -- cleaned up callbacks, which triggers a false-positive
      -- NO_RESULT_CALLBACK_FOUND error on exit.
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not client or client.name ~= "taplo" or client._taplo_error_filter_patched then
            return
          end

          local orig_write_error = client.write_error
          client.write_error = function(self, code, err)
            local no_callback = code == vim.lsp.rpc.client_errors.NO_RESULT_CALLBACK_FOUND
            local shutting_down = type(err) == "table"
              and err.error
              and err.error.data == "server is shutting down"
              and err.error.message == "Invalid request"

            if no_callback and shutting_down then
              return
            end

            return orig_write_error(self, code, err)
          end

          client._taplo_error_filter_patched = true
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
        -- Without Mason, lua_ls starts before lazydev.nvim can set up its
        -- workspace/configuration handler, so it never gets the library paths.
        -- Provide them statically so lua_ls has type info from startup.
        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                library = {
                  vim.env.VIMRUNTIME .. "/lua",
                  vim.fn.stdpath("data") .. "/lazy/LazyVim/lua",
                  vim.fn.stdpath("data") .. "/lazy/lazy.nvim/lua",
                },
              },
            },
          },
        },
        basedpyright = {
          mason = false,
        },
        ruff = {
          mason = false,
        },
      },
    },
  },
}
