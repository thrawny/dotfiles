return {
  {
    "folke/edgy.nvim",
    opts = function(_, opts)
      -- Move DBUI from right sidebar to left sidebar
      opts.right = opts.right or {}
      opts.left = opts.left or {}

      -- Find the dbui entry in opts.right
      local dbui_index = nil
      for i, view in ipairs(opts.right) do
        if view.ft == "dbui" then
          dbui_index = i
          break
        end
      end

      -- If found, remove from right and add to left
      if dbui_index then
        local dbui_view = table.remove(opts.right, dbui_index)
        dbui_view.width = 0.3
        table.insert(opts.left, dbui_view)
      end

      -- Find and modify the existing dbout entry from SQL extra
      opts.bottom = opts.bottom or {}
      for _, view in ipairs(opts.bottom) do
        if view.ft == "dbout" then
          view.size = { height = 0.3 }
          break
        end
      end
    end,
  },
}
