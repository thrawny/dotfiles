return {
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged" },
  opts = {
    enabled = true,
    debounce_delay = 10000, -- ms
    condition = function(buf)
      local fn = vim.fn
      local utils = require("auto-save.utils.data")

      -- Default conditions from the plugin
      if fn.getbufvar(buf, "&modifiable") == 1 and utils.not_in(fn.getbufvar(buf, "&filetype"), {}) then
        return true
      end
      return false
    end,
  },
}
