local go_workspace = require("config.go_workspace")

return {
  "neovim/nvim-lspconfig",
  opts = {
    setup = {
      gopls = function(server, opts)
        -- Register the user settings first so the resolved config also contains
        -- nvim-lspconfig's default gopls command and root-dir callback.
        vim.lsp.config(server, opts)
        local resolved = assert(vim.lsp.config[server])
        local default_cmd = resolved.cmd
        local default_root_dir = resolved.root_dir
        local standalone_roots = {}

        vim.lsp.config(server, {
          root_dir = function(bufnr, on_dir)
            local context = go_workspace.context(vim.api.nvim_buf_get_name(bufnr))
            standalone_roots[context.cwd] = context.standalone or nil
            if context.standalone then
              on_dir(context.cwd)
            else
              default_root_dir(bufnr, on_dir)
            end
          end,
          cmd = function(dispatchers, config)
            local root_dir = config.root_dir and vim.fs.normalize(config.root_dir):gsub("/$", "")
            local env = config.cmd_env
            if root_dir and standalone_roots[root_dir] then
              env = vim.tbl_extend("force", env or {}, { GOWORK = "off" })
            end
            return vim.lsp.rpc.start(default_cmd, dispatchers, {
              cwd = config.cmd_cwd,
              env = env,
              detached = config.detached,
            })
          end,
        })

        vim.lsp.enable(server)
        return true
      end,
    },
    servers = {
      gopls = {
        settings = {
          gopls = {
            usePlaceholders = false,
            analyses = {
              ST1000 = false,
              ST1003 = false,
            },
          },
        },
      },
    },
  },
}
