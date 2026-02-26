-- Find all files including gitignored (but exclude common noise)

local ignored_patterns = {
  "%.git/",
  "%node_modules/",
  "%.venv/",
  "%.DS_Store$",
  "%.ruff_cache/",
  "%target/",
  "%.direnv/",
}

local find_all_files = function()
  require("fzf-lua").files({
    no_ignore = true,
    hidden = true,
    file_ignore_patterns = ignored_patterns,
  })
end

-- Grep in current working directory (with same ignore patterns as find_all_files)
local grep_all_in_cwd = function()
  require("fzf-lua").live_grep({
    cwd = vim.loop.cwd(), ---@diagnostic disable-line: undefined-field
    no_ignore = true,
    hidden = true,
    file_ignore_patterns = ignored_patterns,
  })
end

return {
  {
    "ibhagwan/fzf-lua",
    keys = {
      { "<leader>/", grep_all_in_cwd, desc = "Grep (cwd)" },
    },
    opts = {
      -- Override LazyVim's alt bindings (conflict with window managers)
      files = {
        actions = {
          ["alt-h"] = false,
          ["alt-i"] = false,
          ["ctrl-y"] = { require("fzf-lua").actions.toggle_hidden },
          ["ctrl-o"] = { require("fzf-lua").actions.toggle_ignore },
        },
      },
      grep = {
        actions = {
          ["alt-h"] = false,
          ["alt-i"] = false,
          ["ctrl-y"] = { require("fzf-lua").actions.toggle_hidden },
          ["ctrl-o"] = { require("fzf-lua").actions.toggle_ignore },
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
