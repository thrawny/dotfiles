local merged_picker = require("config.snacks_merged_picker")

local function git_output(args, cwd)
  local cmd = { "git" }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or "")
end

local function open_review_for_main_to_worktree()
  require("lazy").load({ plugins = { "review.nvim" } })

  -- review.nvim has no command for "merge-base(main, HEAD)..working tree",
  -- so open CodeDiff directly while doing the same review store setup.
  require("review.storage").clear_revisions()
  local store = require("review.store")
  store.reset()
  store.load()

  vim.cmd("CodeDiff main...")

  local review = require("review")
  local attempts = 0
  local function apply_review_hooks()
    attempts = attempts + 1
    review._check_codediff_session()

    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if ok and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
      return
    end
    if attempts < 5 then
      vim.defer_fn(apply_review_hooks, 100)
    end
  end
  vim.defer_fn(apply_review_hooks, 200)
end

local function smart_review()
  local root = LazyVim.root()
  local branch = git_output({ "branch", "--show-current" }, root)
  local dirty = git_output({ "status", "--porcelain" }, root)

  if branch == "main" then
    if dirty and dirty ~= "" then
      vim.cmd("Review")
    else
      vim.cmd("Review commits HEAD")
    end
  else
    open_review_for_main_to_worktree()
  end
end

return {
  -- Disable bufferline (top tab view)
  {
    "akinsho/bufferline.nvim",
    enabled = false,
  },

  -- Configure noice for LSP hover borders
  -- Disable cmdline treesitter highlighting (broken with nvim 0.11 query syntax)
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        lsp_doc_border = true,
      },
      cmdline = {
        format = {
          cmdline = { lang = false },
          search_down = { lang = false },
          search_up = { lang = false },
          filter = { lang = false },
          lua = { lang = false },
          help = { lang = false },
        },
      },
      routes = {
        {
          filter = {
            event = "lsp",
            kind = "progress",
            cond = function(message)
              local client = vim.tbl_get(message.opts, "progress", "client")
              return client == "basedpyright"
            end,
          },
          opts = { skip = true },
        },
      },
    },
  },

  -- Configure snacks explorer to show hidden and ignored files by default
  {
    "snacks.nvim",
    keys = {
      { "<leader>S", false },
      {
        "<M-;>",
        function()
          Snacks.terminal(nil, { cwd = LazyVim.root() })
        end,
        mode = { "n", "t" },
        desc = "Terminal (Root Dir)",
      },
      {
        "<leader>ge",
        function()
          Snacks.picker.git_status({ ignored = false })
        end,
        desc = "Git Status (Explorer)",
      },
      {
        "<leader>.",
        function()
          Snacks.picker(merged_picker.opts())
        end,
        desc = "Find + Grep (merged)",
      },
      {
        "<leader>`",
        function()
          Snacks.scratch()
        end,
        desc = "Scratch Buffer",
      },
    },
    opts = {
      styles = {
        dashboard = {
          wo = {
            -- Use the main editor background instead of snacks.nvim's dashboard background.
            winhighlight = "Normal:Normal,NormalFloat:Normal",
          },
        },
      },
      dashboard = {
        preset = {
          -- Replace the LazyVim splash-screen shortcuts with our own set.
          ---@type snacks.dashboard.Item[]
          keys = {
            {
              icon = " ",
              key = ".",
              desc = "Find + Grep",
              action = function()
                Snacks.picker(merged_picker.opts())
              end,
            },
            {
              icon = " ",
              key = "g",
              desc = "LazyGit",
              action = function()
                Snacks.lazygit({ cwd = LazyVim.root() })
              end,
            },
            { icon = "󰈙 ", key = "r", desc = "Review", action = smart_review },
            { icon = " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
      },
      picker = {
        hidden = true, -- Show hidden files by default
        ignored = true, -- Show gitignored files by default
        exclude = { ".DS_Store" },
        win = {
          input = {
            keys = {
              ["<c-g>"] = false,
            },
          },
          list = {
            keys = {
              ["<c-g>"] = false,
            },
          },
        },
      },
      terminal = {
        win = {
          keys = {
            -- Add M-; as a hide action when in terminal mode (same as C-/)
            hide_alt_semicolon = { "<M-;>", "hide", desc = "Hide Terminal", mode = { "t", "n" } },
          },
        },
      },
      lazygit = {
        win = {
          width = 0,
          height = 0,
        },
      },
    },
  },
}
