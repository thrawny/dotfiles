local function has(bin)
  return vim.fn.executable(bin) == 1
end

local use_tofu = has("tofu")
local formatter = use_tofu and "tofu_fmt" or (has("terraform") and "terraform_fmt" or nil)
local linter = use_tofu and "tofu" or (has("terraform") and "terraform_validate" or nil)

local lsp_server
if use_tofu and has("tofu-ls") then
  lsp_server = "tofu_ls"
elseif has("terraform-ls") then
  lsp_server = "terraformls"
elseif has("tofu-ls") then
  lsp_server = "tofu_ls"
end

local tf_filetypes = { "terraform", "tf", "terraform-vars", "opentofu", "opentofu-vars" }

return {
  {
    "neovim/nvim-lspconfig",
    optional = true,
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.tofu_ls = lsp_server == "tofu_ls" and (opts.servers.tofu_ls or {}) or false
      opts.servers.terraformls = lsp_server == "terraformls" and (opts.servers.terraformls or {}) or false
    end,
  },

  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      if not formatter then
        return
      end
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      for _, ft in ipairs(tf_filetypes) do
        opts.formatters_by_ft[ft] = { formatter }
      end
    end,
  },

  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      if not linter then
        return
      end
      opts.linters_by_ft = opts.linters_by_ft or {}
      for _, ft in ipairs(tf_filetypes) do
        opts.linters_by_ft[ft] = { linter }
      end
    end,
  },
}
