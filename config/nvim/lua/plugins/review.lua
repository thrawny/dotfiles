local codediff_dir = vim.fn.expand("~/code/codediff.nvim")
local codediff_plugin_name = "codediff.nvim"
local codediff_spec = {
  name = codediff_plugin_name,
}

if (vim.uv or vim.loop).fs_stat(codediff_dir) then
  codediff_spec.dir = codediff_dir
else
  codediff_spec[1] = "thrawny/codediff.nvim"
  codediff_spec.branch = "main"
end

local review_opts = {
  keymaps = {
    next_file = false,
    prev_file = false,
  },
  codediff = {
    focus_modified_pane = false,
  },
  popup = {
    show_type_selector = false,
  },
  export = {
    format = "compact",
  },
}

return {
  vim.tbl_extend("force", codediff_spec, {
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    cmd = { "CodeDiff", "CodeReview", "Review" },
    config = function(_, opts)
      require("codediff").setup(opts)
      require("codediff.review").setup(review_opts)
    end,
    init = function()
      -- Custom tabline: show "Review" for codediff tabs
      vim.o.tabline = "%!v:lua.require'config.codediff_tabline'()"
    end,
    keys = function()
      return {
        {
          "<leader>rr",
          function()
            require("codediff.review").toggle({ preview = true })
          end,
          desc = "Review",
        },
        {
          "<leader>rm",
          function()
            require("codediff.review").open_merge_base("origin/main", "HEAD")
          end,
          desc = "Review branch changes",
        },
        { "<leader>rc", "<cmd>Review commits<cr>", desc = "Review commits" },
        { "<leader>rp", "<cmd>Review pr<cr>", desc = "Review GitHub PR" },
        {
          "<leader>rf",
          function()
            local _, _, session = require("codediff.review").current_session()
            local current_buf = vim.api.nvim_get_current_buf()
            if not session or (current_buf ~= session.original_bufnr and current_buf ~= session.modified_bufnr) then
              vim.notify("Focus a review diff pane to open its file", vim.log.levels.WARN)
              return
            end

            local mapping = vim.fn.maparg("gf", "n", false, true)
            if type(mapping) ~= "table" or type(mapping.callback) ~= "function" then
              vim.notify("The CodeDiff open-file mapping is unavailable", vim.log.levels.WARN)
              return
            end
            mapping.callback()
          end,
          desc = "Review file in normal buffer",
        },
        {
          "<leader>re",
          function()
            require("codediff.review").export_clipboard({ preview = false })
          end,
          desc = "Review export",
        },
        {
          "<leader>rx",
          function()
            require("codediff.review").close({ clear = true, preview = false, noop_if_inactive = true })
          end,
          desc = "Review close + clear",
        },
      }
    end,
    opts = {
      highlights = {
        line_insert = "#004466",
        line_delete = "#660100",
      },
      diff = {
        layout = "inline",
        show_hunk_navigation_message = false,
        semantic_tokens = false,
        winbar = {
          enabled = true,
        },
      },
      explorer = {
        view_mode = "tree",
      },
      keymaps = {
        view = {
          next_hunk = "}",
          prev_hunk = "{",
          next_hunk_or_file = { "<Tab>", "<C-i>" },
          prev_hunk_or_file = "<S-Tab>",
          next_file = "<C-n>",
          prev_file = "<C-p>",
        },
      },
    },
  }),

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
