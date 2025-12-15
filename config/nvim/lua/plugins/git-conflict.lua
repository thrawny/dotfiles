return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPre",
  config = function()
    require("git-conflict").setup()

    -- Disable LSP diagnostics when conflicts are detected
    vim.api.nvim_create_autocmd("User", {
      pattern = "GitConflictDetected",
      callback = function(args)
        vim.diagnostic.enable(false, { bufnr = args.buf })
        vim.notify("LSP diagnostics disabled (conflict detected)", vim.log.levels.INFO)
      end,
    })

    -- Re-enable when conflicts are resolved
    vim.api.nvim_create_autocmd("User", {
      pattern = "GitConflictResolved",
      callback = function(args)
        vim.diagnostic.enable(true, { bufnr = args.buf })
      end,
    })
  end,
}
