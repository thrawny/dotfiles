return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      preset = "default",
      ["<Tab>"] = {
        LazyVim.cmp.map({ "ai_nes", "ai_accept" }),
        function(cmp)
          if cmp.snippet_active() then
            return cmp.accept()
          else
            return cmp.select_and_accept()
          end
        end,
        "fallback",
      },
      -- ["<CR>"] = { "accept", "fallback" },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
    },
  },
}
