-- Find all files including gitignored (but exclude common noise)
local find_all_files = function()
  require("fzf-lua").files({
    no_ignore = true,
    hidden = true,
    file_ignore_patterns = {
      "%.git/",
      "node_modules/",
      "%.venv/",
      "%.DS_Store$",
      "%.ruff_cache/",
    },
  })
end

-- Grep in current working directory (with same ignore patterns as find_all_files)
local grep_all_in_cwd = function()
  require("fzf-lua").live_grep({
    cwd = vim.loop.cwd(), ---@diagnostic disable-line: undefined-field
    no_ignore = true,
    hidden = true,
    file_ignore_patterns = {
      "%.git/",
      "node_modules/",
      "%.venv/",
      "%.DS_Store$",
      "%.ruff_cache/",
    },
  })
end

return {
  {
    "ibhagwan/fzf-lua",
    keys = {
      { "<leader>.", find_all_files, desc = "Find Files (all)" },
      { "<leader>/", grep_all_in_cwd, desc = "Grep (cwd)" },
    },
    opts = {
      actions = {
        files = {
          true, -- Inherit all default actions (enter, ctrl-s, ctrl-v, etc.)
          ["alt-h"] = false, -- Disable default alt-h (conflicts with window manager)
          ["alt-u"] = require("fzf-lua").actions.toggle_hidden,
        },
      },
    },
    config = function(_, opts)
      require("fzf-lua").setup(opts)

      -- Re-assert our buffer toggle keymap after fzf loads
      -- This overrides fzf's <leader>, keymap for buffer switcher
      vim.keymap.set("n", "<leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

      -- Find files keybindings
      vim.keymap.set("n", "<leader>fF", find_all_files, { desc = "Find Files (all)" })
    end,
  },
}
