return {
  "saghen/blink.cmp",
  opts = {
    keymap = {
      preset = "default",
      ["<Tab>"] = {
        function(cmp)
          if cmp.snippet_active() then
            return cmp.accept()
          else
            return cmp.select_and_accept()
          end
        end,
        LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" }),
        "fallback",
      },
      ["<S-Tab>"] = { "snippet_backward", "fallback" },
    },
  },
}
