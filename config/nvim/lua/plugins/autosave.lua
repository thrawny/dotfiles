return {
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged" },
  opts = {
    enabled = true,
    trigger_events = {
      immediate_save = { "BufLeave", "FocusLost" },
      defer_save = { "InsertLeave", "TextChanged" },
    },
    debounce_delay = 1000, -- ms
    condition = function(buf)
      local fn = vim.fn
      local utils = require("auto-save.utils.data")

      -- Don't autosave for Harpoon
      if vim.bo[buf].filetype == "harpoon" then
        return false
      end

      -- Default conditions from the plugin
      if fn.getbufvar(buf, "&modifiable") == 1 and utils.not_in(fn.getbufvar(buf, "&filetype"), {}) then
        return true
      end
      return false
    end,
  },
}
