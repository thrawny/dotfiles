return {
  {
    "ibhagwan/fzf-lua",
    config = function(_, opts)
      require("fzf-lua").setup(opts)

      -- Re-assert our buffer toggle keymap after fzf loads
      -- This overrides fzf's <leader>, keymap for buffer switcher
      vim.keymap.set("n", "<leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

      -- Find files including gitignored (but exclude node_modules, .venv, .git)
      vim.keymap.set("n", "<leader>fF", function()
        require("fzf-lua").files({
          no_ignore = true,
          hidden = true,
          file_ignore_patterns = {
            "^%.git/",
            "node_modules/",
            "%.venv/",
            "%.DS_Store$",
            "%.ruff_cache/",
          },
        })
      end, { desc = "Find Files (all)" })
    end,
  },
}
