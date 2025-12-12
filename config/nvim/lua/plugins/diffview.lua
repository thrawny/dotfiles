return {
  "sindrets/diffview.nvim",
  enabled = false,
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh" },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
    { "<leader>gD", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
    { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "File History (current)" },
  },
  opts = function()
    local actions = require("diffview.actions")
    return {
      enhanced_diff_hl = true,
      view = {
        merge_tool = {
          layout = "diff3_mixed",
        },
      },
      keymaps = {
        view = {
          { "n", "]h", function() vim.cmd.normal({ "]c", bang = true }) end, { desc = "Next Hunk" } },
          { "n", "[h", function() vim.cmd.normal({ "[c", bang = true }) end, { desc = "Prev Hunk" } },
          { "n", "<leader>co", actions.conflict_choose("ours"), { desc = "Choose OURS" } },
          { "n", "<leader>ct", actions.conflict_choose("theirs"), { desc = "Choose THEIRS" } },
          { "n", "<leader>cb", actions.conflict_choose("base"), { desc = "Choose BASE" } },
          { "n", "<leader>ca", actions.conflict_choose("all"), { desc = "Choose ALL" } },
          { "n", "<leader>cn", actions.conflict_choose("none"), { desc = "Choose NONE" } },
        },
        file_panel = {
          { "n", "<C-d>", actions.scroll_view(0.5), { desc = "Scroll view half-page down" } },
          { "n", "<C-u>", actions.scroll_view(-0.5), { desc = "Scroll view half-page up" } },
          {
            "n",
            "]h",
            function()
              local cur = vim.api.nvim_get_current_win()
              for _, dir in ipairs({ "l", "h" }) do
                pcall(vim.cmd.wincmd, dir)
                pcall(vim.cmd.normal, { "]c", bang = true })
              end
              vim.api.nvim_set_current_win(cur)
            end,
            { desc = "Next Hunk (in diff views)" },
          },
          {
            "n",
            "[h",
            function()
              local cur = vim.api.nvim_get_current_win()
              for _, dir in ipairs({ "l", "h" }) do
                pcall(vim.cmd.wincmd, dir)
                pcall(vim.cmd.normal, { "[c", bang = true })
              end
              vim.api.nvim_set_current_win(cur)
            end,
            { desc = "Prev Hunk (in diff views)" },
          },
        },
        file_history_panel = {
          { "n", "<C-d>", actions.scroll_view(0.5), { desc = "Scroll view half-page down" } },
          { "n", "<C-u>", actions.scroll_view(-0.5), { desc = "Scroll view half-page up" } },
        },
      },
      hooks = {
        diff_buf_read = function(bufnr)
          vim.opt_local.relativenumber = false
          vim.opt_local.number = true
          vim.opt_local.cursorline = true
          vim.opt_local.foldenable = false
        end,
        diff_buf_win_enter = function(bufnr, winid, ctx)
          vim.wo[winid].foldenable = false
          -- Colorblind-friendly: left=red, right=blue (only on changed lines)
          -- Lowercase a/b for regular diffs, uppercase A/C for merge conflicts (OURS/THEIRS)
          if ctx.symbol == "a" or ctx.symbol == "A" then
            vim.wo[winid].winhighlight = table.concat({
              "DiffAdd:DiffLineLeft",
              "DiffChange:DiffLineLeft",
              "DiffText:DiffTextLeft",
              "DiffDelete:DiffEmpty",
            }, ",")
          elseif ctx.symbol == "b" or ctx.symbol == "C" then
            vim.wo[winid].winhighlight = table.concat({
              "DiffAdd:DiffLineRight",
              "DiffChange:DiffLineRight",
              "DiffText:DiffTextRight",
              "DiffDelete:DiffEmpty",
            }, ",")
          end
        end,
      },
    }
  end,
  config = function(_, opts)
    vim.opt.diffopt:append({ "algorithm:histogram", "linematch:60" })
    vim.opt.fillchars:append({ diff = " " })

    -- Colorblind-friendly palette (red vs blue)
    -- Only changed lines get colored
    vim.api.nvim_set_hl(0, "DiffLineLeft", { bg = "#4d0a0a" }) -- red bg
    vim.api.nvim_set_hl(0, "DiffTextLeft", { bg = "#801515" }) -- brighter red inline

    vim.api.nvim_set_hl(0, "DiffLineRight", { bg = "#0a2a4d" }) -- blue bg
    vim.api.nvim_set_hl(0, "DiffTextRight", { bg = "#154580" }) -- brighter blue inline

    -- Invisible filler for deleted lines
    vim.api.nvim_set_hl(0, "DiffEmpty", {})

    require("diffview").setup(opts)
  end,
}
