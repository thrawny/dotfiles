return {
  {
    "esmuellert/codediff.nvim",
    init = function()
      -- Monkeypatch: replace codediff's winbar-clearing autocmd with one that sets our winbar
      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeDiffOpen",
        callback = function()
          vim.defer_fn(function()
            local tabpage = vim.api.nvim_get_current_tabpage()
            local lifecycle = require("codediff.ui.lifecycle")
            local sess = lifecycle.get_session(tabpage)
            if not sess then
              return
            end

            -- Replace the lifecycle augroup to stop winbar clearing
            local group_name = "codediff_lifecycle_tab_" .. tabpage
            local group = vim.api.nvim_create_augroup(group_name, { clear = true })

            local welcome_ok, welcome_window = pcall(require, "codediff.ui.welcome_window")
            local accessors = require("codediff.ui.lifecycle.accessors")
            local state_ok, state = pcall(require, "codediff.ui.view.state")

            -- Preserve original window sync (minus winbar clearing)
            vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinEnter", "FileType" }, {
              group = group,
              callback = function()
                local s = lifecycle.get_session(tabpage)
                if not s then
                  return
                end
                local win = vim.api.nvim_get_current_win()
                if win == s.modified_win or win == s.original_win then
                  vim.wo[win].wrap = false
                  if welcome_ok then
                    welcome_window.sync(win)
                  end
                end
              end,
            })

            -- Preserve TabLeave/TabEnter for keymap and diff suspension
            vim.api.nvim_create_autocmd("TabLeave", {
              group = group,
              callback = function()
                if vim.api.nvim_get_current_tabpage() == tabpage then
                  accessors.clear_tab_keymaps(tabpage)
                  if state_ok then
                    state.suspend_diff(tabpage)
                  end
                end
              end,
            })
            vim.api.nvim_create_autocmd("TabEnter", {
              group = group,
              callback = function()
                vim.schedule(function()
                  if vim.api.nvim_get_current_tabpage() == tabpage then
                    local s = lifecycle.get_session(tabpage)
                    if s and s.reapply_keymaps then
                      pcall(s.reapply_keymaps)
                    end
                    if state_ok then
                      state.resume_diff(tabpage)
                    end
                  end
                end)
              end,
            })

            -- Set winbar on cursor move (no flicker since codediff no longer clears it)
            vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
              group = group,
              callback = function()
                local s = lifecycle.get_session(tabpage)
                if not s then
                  return
                end
                local win = vim.api.nvim_get_current_win()
                if win ~= s.modified_win and win ~= s.original_win then
                  return
                end

                local parts = {}
                local explorer = lifecycle.get_explorer(tabpage)
                if explorer and explorer.tree then
                  local refresh = require("codediff.ui.explorer.refresh")
                  local all_files = refresh.get_all_files(explorer.tree)
                  local current = explorer.current_file_path
                  for i, f in ipairs(all_files) do
                    if f.data and f.data.path == current then
                      table.insert(parts, string.format("\u{f0214} %d/%d  %s", i, #all_files, current))
                      break
                    end
                  end
                end
                local diff_result = s.stored_diff_result
                if diff_result and diff_result.changes and #diff_result.changes > 0 then
                  local cursor = vim.api.nvim_win_get_cursor(0)[1]
                  local current_hunk = 0
                  for i, mapping in ipairs(diff_result.changes) do
                    if cursor >= mapping.modified.start_line then
                      current_hunk = i
                    end
                  end
                  if current_hunk > 0 then
                    table.insert(parts, string.format("\u{f4d2} %d/%d", current_hunk, #diff_result.changes))
                  end
                end
                vim.wo[win].winbar = "%=" .. table.concat(parts, "  ") .. "%="
              end,
            })
          end, 200)
        end,
      })

      vim.api.nvim_create_autocmd("User", {
        pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
        callback = function()
          vim.defer_fn(function()
            local tabpage = vim.api.nvim_get_current_tabpage()
            local lifecycle = require("codediff.ui.lifecycle")
            local nav = require("codediff.ui.view.navigation")
            local function on_last_hunk()
              local sess = lifecycle.get_session(tabpage)
              if not sess or not sess.stored_diff_result then
                return true
              end
              local changes = sess.stored_diff_result.changes
              if not changes or #changes == 0 then
                return true
              end
              local cursor = vim.api.nvim_win_get_cursor(0)[1]
              return cursor >= changes[#changes].modified.start_line
            end
            local function on_first_hunk()
              local sess = lifecycle.get_session(tabpage)
              if not sess or not sess.stored_diff_result then
                return true
              end
              local changes = sess.stored_diff_result.changes
              if not changes or #changes == 0 then
                return true
              end
              local cursor = vim.api.nvim_win_get_cursor(0)[1]
              return cursor <= changes[1].modified.start_line
            end
            -- Suppress codediff's echo messages during navigation
            local orig_echo = vim.api.nvim_echo
            local function silent_nav(fn)
              vim.api.nvim_echo = function() end
              local ok, err = pcall(fn)
              vim.api.nvim_echo = orig_echo
              if not ok then
                error(err)
              end
            end
            lifecycle.set_tab_keymap(tabpage, "n", "<Tab>", function()
              silent_nav(function()
                if on_last_hunk() then
                  nav.next_file()
                else
                  nav.next_hunk()
                end
              end)
            end, { desc = "Next hunk (cross-file)" })
            lifecycle.set_tab_keymap(tabpage, "n", "<S-Tab>", function()
              silent_nav(function()
                if on_first_hunk() then
                  nav.prev_file()
                else
                  nav.prev_hunk()
                end
              end)
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

  -- Remap {/} to hunk navigation in normal buffers (gitsigns)
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      ---@diagnostic disable-next-line: param-type-mismatch
      {
        "}",
        function()
          require("gitsigns").nav_hunk("next")
        end,
        desc = "Next Hunk",
      },
      ---@diagnostic disable-next-line: param-type-mismatch
      {
        "{",
        function()
          require("gitsigns").nav_hunk("prev")
        end,
        desc = "Prev Hunk",
      },
    },
  },
}
