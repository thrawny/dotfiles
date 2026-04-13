return {
  {
    "esmuellert/codediff.nvim",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
        callback = function()
          vim.defer_fn(function()
            local tabpage = vim.api.nvim_get_current_tabpage()
            local lifecycle = require("codediff.ui.lifecycle")
            local nav = require("codediff.ui.view.navigation")
            local function on_last_hunk()
              local sess = lifecycle.get_session(tabpage)
              if not sess or not sess.stored_diff_result then return true end
              local changes = sess.stored_diff_result.changes
              if not changes or #changes == 0 then return true end
              local cursor = vim.api.nvim_win_get_cursor(0)[1]
              return cursor >= changes[#changes].modified.start_line
            end
            local function on_first_hunk()
              local sess = lifecycle.get_session(tabpage)
              if not sess or not sess.stored_diff_result then return true end
              local changes = sess.stored_diff_result.changes
              if not changes or #changes == 0 then return true end
              local cursor = vim.api.nvim_win_get_cursor(0)[1]
              return cursor <= changes[1].modified.start_line
            end
            lifecycle.set_tab_keymap(tabpage, "n", "<Tab>", function()
              if on_last_hunk() then nav.next_file() else nav.next_hunk() end
            end, { desc = "Next hunk (cross-file)" })
            lifecycle.set_tab_keymap(tabpage, "n", "<S-Tab>", function()
              if on_first_hunk() then nav.prev_file() else nav.prev_hunk() end
            end, { desc = "Prev hunk (cross-file)" })
            lifecycle.set_tab_keymap(tabpage, "n", "<C-n>", function()
              nav.next_file()
            end, { desc = "Next file" })
            lifecycle.set_tab_keymap(tabpage, "n", "<C-p>", function()
              nav.prev_file()
            end, { desc = "Prev file" })
          end, 300)
        end,
      })
    end,
    opts = {
      highlights = {
        line_insert = "#004466",
        line_delete = "#660100",
      },
      diff = {
        layout = "inline",

      },
      keymaps = {
        view = {
          next_hunk = "}",
          prev_hunk = "{",
        },
      },
    },
  },

  {
    "georgeguimaraes/review.nvim",
    dependencies = {
      "esmuellert/codediff.nvim",
      "MunifTanjim/nui.nvim",
    },
    cmd = { "Review" },
    keys = {
      { "<leader>r", "<cmd>Review<cr>", desc = "Review" },
      { "<leader>R", "<cmd>Review commits<cr>", desc = "Review commits" },
    },
    opts = {},
  },

  -- Show file/hunk position in lualine for codediff tabs
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function codediff_position()
        local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
        if not ok then return "" end
        local tabpage = vim.api.nvim_get_current_tabpage()
        local sess = lifecycle.get_session(tabpage)
        if not sess then return "" end

        local parts = {}

        -- File position
        local explorer = lifecycle.get_explorer(tabpage)
        if explorer and explorer.tree then
          local refresh = require("codediff.ui.explorer.refresh")
          local all_files = refresh.get_all_files(explorer.tree)
          local current = explorer.current_file_path
          for i, f in ipairs(all_files) do
            if f.data and f.data.path == current then
              table.insert(parts, string.format("󰈔 %d/%d", i, #all_files))
              break
            end
          end
        end

        -- Hunk position
        local diff_result = sess.stored_diff_result
        if diff_result and diff_result.changes and #diff_result.changes > 0 then
          local cursor = vim.api.nvim_win_get_cursor(0)[1]
          local current_hunk = 0
          for i, mapping in ipairs(diff_result.changes) do
            if cursor >= mapping.modified.start_line then
              current_hunk = i
            end
          end
          if current_hunk > 0 then
            table.insert(parts, string.format(" %d/%d", current_hunk, #diff_result.changes))
          end
        end

        return table.concat(parts, "  ")
      end

      table.insert(opts.sections.lualine_x, 1, {
        codediff_position,
        cond = function()
          local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
          if not ok then return false end
          return lifecycle.get_session(vim.api.nvim_get_current_tabpage()) ~= nil
        end,
      })
    end,
  },

  -- Remap {/} to hunk navigation in normal buffers (gitsigns)
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      ---@diagnostic disable-next-line: param-type-mismatch
      { "}", function() require("gitsigns").nav_hunk("next") end, desc = "Next Hunk" },
      ---@diagnostic disable-next-line: param-type-mismatch
      { "{", function() require("gitsigns").nav_hunk("prev") end, desc = "Prev Hunk" },
    },
  },
}
