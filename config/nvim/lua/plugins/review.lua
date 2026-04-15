return {
  {
    dir = vim.fn.expand("~/code/codediff.nvim"),
    name = "esmuellert/codediff.nvim",
    config = function(_, opts)
      require("codediff").setup(opts)
    end,
    init = function()
      -- Custom tabline: show "Review" for codediff tabs
      vim.o.tabline = "%!v:lua.require'config.codediff_tabline'()"

      -- Monkeypatch: replace codediff's winbar-clearing autocmd with one that sets our winbar
      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeDiffOpen",
        callback = function(ev)
          vim.defer_fn(function()
            local tabpage = ev.data and ev.data.tabpage or vim.api.nvim_get_current_tabpage()
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
        pattern = { "CodeDiffOpen", "CodeDiffRender" },
        callback = function(ev)
          local tabpage = ev.data and ev.data.tabpage or vim.api.nvim_get_current_tabpage()
          vim.schedule(function()
            if not vim.api.nvim_tabpage_is_valid(tabpage) then
              return
            end
            local lifecycle = require("codediff.ui.lifecycle")
            if not lifecycle.get_session(tabpage) then
              return
            end
            local nav = require("codediff.ui.view.navigation")
            lifecycle.set_tab_keymap(tabpage, "n", "<Tab>", nav.next_hunk_or_file, { desc = "Next hunk or file" })
            lifecycle.set_tab_keymap(tabpage, "n", "<C-i>", nav.next_hunk_or_file, { desc = "Next hunk or file" })
            lifecycle.set_tab_keymap(tabpage, "n", "<S-Tab>", nav.prev_hunk_or_file, { desc = "Prev hunk or file" })
          end)
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
          next_hunk_or_file = "<Tab>",
          prev_hunk_or_file = "<S-Tab>",
          next_file = "<C-n>",
          prev_file = "<C-p>",
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
    config = function(_, opts)
      require("review").setup(opts)
      require("config.review_monkeypatch").apply()
    end,
    keys = function()
      local function restore_review_buffers(lifecycle, tabpage)
        local orig_buf, mod_buf = lifecycle.get_buffers(tabpage)
        for _, buf in ipairs({ orig_buf, mod_buf }) do
          if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
            vim.api.nvim_set_option_value("readonly", false, { buf = buf })
          end
        end
      end

      local function export_review_to_clipboard_only()
        local store = require("review.store")
        local count = store.count()
        if count == 0 then
          vim.notify("No comments to export", vim.log.levels.WARN, { title = "review.nvim" })
          return
        end

        local markdown = require("review.export").generate_markdown()
        vim.fn.setreg("+", markdown)
        vim.fn.setreg("*", markdown)
        vim.notify(
          string.format("Exported %d comment(s) to clipboard", count),
          vim.log.levels.INFO,
          { title = "review.nvim" }
        )
      end

      return {
        {
          "<leader>rr",
          function()
            local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
            local tabpage = vim.api.nvim_get_current_tabpage()
            if ok and lifecycle.get_session(tabpage) then
              restore_review_buffers(lifecycle, tabpage)
              require("review").close()
            else
              local status = vim.fn.system({ "git", "status", "--porcelain" })
              if vim.v.shell_error == 0 and vim.trim(status) == "" then
                vim.cmd("Review commits HEAD")
              else
                vim.cmd("Review")
              end
            end
          end,
          desc = "Review",
        },
        { "<leader>rm", "<cmd>Review commits main HEAD<cr>", desc = "Review main..HEAD" },
        { "<leader>rc", "<cmd>Review commits<cr>", desc = "Review commits" },
        {
          "<leader>re",
          export_review_to_clipboard_only,
          desc = "Review export",
        },
        {
          "<leader>rx",
          function()
            local review = require("review")
            local lifecycle = require("codediff.ui.lifecycle")
            local tabpage = vim.api.nvim_get_current_tabpage()
            export_review_to_clipboard_only()
            restore_review_buffers(lifecycle, tabpage)
            review.clear()
            vim.cmd("tabclose")
            require("review.hooks").on_session_closed()
            require("review.storage").clear_revisions()
          end,
          desc = "Review close + clear",
        },
      }
    end,
    opts = {
      keymaps = {
        next_file = false,
        prev_file = false,
      },
    },
  },

  -- Remap {/} to hunk navigation in normal buffers (gitsigns)
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      {
        "}",
        function()
          ---@diagnostic disable-next-line: param-type-mismatch
          require("gitsigns").nav_hunk("next")
        end,
        desc = "Next Hunk",
      },
      {
        "{",
        function()
          ---@diagnostic disable-next-line: param-type-mismatch
          require("gitsigns").nav_hunk("prev")
        end,
        desc = "Prev Hunk",
      },
    },
  },
}
