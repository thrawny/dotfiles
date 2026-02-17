-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Disable spell by default but keep LazyVim's wrap behavior (toggle spell with ,us)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.spell = false
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
  end,
  desc = "Disable spell, add word-boundary wrapping for text filetypes",
})

-- Auto-reload files when changed externally
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
  desc = "Check if file changed externally",
})

-- Notification when file reloads
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  pattern = "*",
  callback = function()
    vim.notify("File reloaded: " .. vim.fn.expand("%"), vim.log.levels.INFO)
  end,
  desc = "Notify when file changed on disk",
})

-- Auto-close terminal buffers when exiting to prevent "job is still running" warnings
vim.api.nvim_create_autocmd("QuitPre", {
  callback = function()
    local wins = vim.api.nvim_list_wins()
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == "terminal" then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end,
  desc = "Force close terminal buffers on quit",
})

-- Disable format-on-save for SQL and JSON files (manual formatting still available via ,cf)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sql", "json", "jsonc" },
  callback = function()
    vim.schedule(function()
      vim.b.autoformat = false
    end)
  end,
  desc = "Disable autoformat for SQL and JSON files",
})

-- Display tabs as 4 spaces in Go files (Go uses real tabs, this controls visual width)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "go" },
  callback = function()
    vim.opt_local.tabstop = 4
  end,
  desc = "Set tab width to 4 for Go files",
})

-- Wipe dadbod-ui special buffers before session save (they can't be restored properly)
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local ft = vim.bo[buf].filetype
        if ft == "dbui" or ft == "dbout" then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
  end,
  desc = "Remove dadbod-ui special buffers before session save",
})

-- After session restore, re-associate dadbod query buffers with their connections.
-- Dadbod tmp query files have no extension so filetype detection fails, and
-- buffer-local connection vars (b:db, b:dbui_db_key_name) are lost.
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = function()
    vim.schedule(function()
      local save_path = vim.fn.stdpath("data") .. "/dadbod_ui"
      local tmp_path = save_path .. "/tmp"

      local query_bufs = {}
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf):find(save_path, 1, true) then
          table.insert(query_bufs, buf)
        end
      end
      if #query_bufs == 0 then return end

      require("lazy").load({ plugins = { "vim-dadbod", "vim-dadbod-ui", "vim-dadbod-completion" } })

      -- connections_list() triggers s:init() to load saved connections without opening the drawer
      local conn_by_name = {}
      for _, c in ipairs(vim.fn["db_ui#connections_list"]()) do
        conn_by_name[c.name] = c.name .. "_" .. c.source
      end

      for _, buf in ipairs(query_bufs) do
        local path = vim.api.nvim_buf_get_name(buf)
        local parent = vim.fn.fnamemodify(path, ":h")
        local db_name

        if vim.fn.fnamemodify(parent, ":h") == save_path then
          db_name = vim.fn.fnamemodify(parent, ":t")
        elseif parent == tmp_path then
          local filename = vim.fn.fnamemodify(path, ":t")
          for name in pairs(conn_by_name) do
            if filename:find("^" .. vim.pesc(name) .. "%-") then
              db_name = name
              break
            end
          end
        end

        local key = db_name and conn_by_name[db_name]
        if key then
          local info = vim.fn["db_ui#get_conn_info"](key)
          if info.conn and info.conn ~= "" then
            vim.b[buf].dbui_db_key_name = key
            vim.b[buf].db = info.conn
          end
        end

        -- Set/re-trigger filetype so treesitter + dadbod ftplugin apply
        vim.api.nvim_buf_call(buf, function()
          if vim.bo.filetype ~= "sql" then
            vim.bo.filetype = "sql"
          else
            vim.cmd("doautocmd FileType sql")
          end
        end)
      end
    end)
  end,
  desc = "Restore dadbod-ui query buffer connections after session load",
})

-- Detect bun shebang and set filetype to typescript
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*",
  callback = function()
    local first_line = vim.fn.getline(1)
    if first_line:match("^#!.*bun") then
      vim.bo.filetype = "typescript"
    end
  end,
  desc = "Set typescript filetype for files with bun shebang",
})
