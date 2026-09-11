return {
  "saghen/blink.cmp",
  opts = {
    -- Completion is opt-in per buffer via :ToggleCompletion.
    enabled = function()
      return vim.b.completion == true
    end,
    cmdline = { enabled = false },
    completion = { ghost_text = { enabled = false } },
    keymap = {
      preset = "default",
      ["<Tab>"] = {
        function(cmp)
          if cmp.snippet_active() then
            return cmp.accept()
          elseif cmp.is_visible() then
            return cmp.select_and_accept()
          end
        end,
        "fallback",
      },
      ["<CR>"] = { "accept", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
    },
  },
}
