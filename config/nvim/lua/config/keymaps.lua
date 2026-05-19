-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle between current and alternate buffer (and center cursor)
vim.keymap.set("n", "<Leader>,", "<C-^>zz", { desc = "Toggle to alternate buffer" })

-- Jump to previous/next location (across buffers, like VSCode)
vim.keymap.set("n", "[e", "<C-o>", { desc = "Previous jump location", silent = true })
vim.keymap.set("n", "]e", "<C-i>", { desc = "Next jump location", silent = true })

-- Clipboard copy/paste (works in normal, visual, and operator-pending modes)
vim.keymap.set({ "n", "v", "o" }, "<space>y", '"+y', { desc = "Yank to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>Y", '"+Y', { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>p", '"+p', { desc = "Paste from system clipboard" })
vim.keymap.set({ "n", "v", "o" }, "<space>P", '"+P', { desc = "Paste before from system clipboard" })

-- Keep cursor centered during search navigation
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })

-- Clear search highlighting
vim.keymap.set("n", "<Leader>o", ":noh<CR>", { desc = "Clear search highlighting", silent = true })

-- Terminal mode: Ctrl+A goes to start of line (shell behavior)
vim.keymap.set("t", "<C-a>", "<Home>", { desc = "Go to start of line in terminal" })

-- Leave Ctrl+G available for the interactive-shell overlay handoff.
-- Disable Neovim's built-in Ctrl+G behavior across common modes.
vim.keymap.set({ "n", "x", "s", "o", "i", "c", "t" }, "<C-g>", "<Nop>", { desc = "Unbind Ctrl+G" })

-- Reload workspace after external file changes (e.g. after an AI coding session)
-- Force-stops LSP, reloads all buffers from disk, clears diagnostics, then restarts.
-- This avoids the stale-buffer problem where LspRestart alone sends outdated content
-- to the new gopls, putting it in an inconsistent state.
local reload_workspace_key = "<Leader>W"
local function reload_workspace()
  -- Force-stop all LSP clients (not just restart, to avoid race conditions)
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end

  -- Delete buffers for files that no longer exist on disk
  local removed = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.filereadable(name) == 0 then
        vim.api.nvim_buf_delete(buf, { force = true })
        removed = removed + 1
      end
    end
  end

  -- Reload remaining buffers from disk so LSP gets fresh content
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modifiable and vim.api.nvim_buf_get_name(buf) ~= "" then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("edit!")
      end)
    end
  end

  -- Clear stale diagnostics from the old LSP session
  vim.diagnostic.reset()

  -- Restart LSP after gopls has fully terminated
  vim.defer_fn(function()
    vim.cmd("edit")
    local msg = "Workspace reloaded"
    if removed > 0 then
      msg = msg .. " (cleaned " .. removed .. " stale buffers)"
    end
    vim.notify(msg)
  end, 300)
end

local reload_workspace_opts = { desc = "Reload workspace (buffers + LSP)", silent = true }
vim.keymap.set("n", reload_workspace_key, reload_workspace, reload_workspace_opts)

-- Some LSP/filetype plugins install buffer-local maps after startup. Buffer-local maps
-- beat global maps, so re-assert this binding as buffer-local whenever entering a
-- normal file buffer to keep plugin maps (for example rename-file maps) from taking it.
vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach" }, {
  group = vim.api.nvim_create_augroup("ReloadWorkspaceKeymap", { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype == "" then
      vim.keymap.set(
        "n",
        reload_workspace_key,
        reload_workspace,
        vim.tbl_extend("force", reload_workspace_opts, { buffer = args.buf })
      )
    end
  end,
})

-- Toggle blink.cmp completion for current buffer
vim.api.nvim_create_user_command("ToggleCompletion", function()
  if vim.b.completion == false then
    vim.b.completion = true
  else
    vim.b.completion = false
  end
  vim.notify("Completion " .. (vim.b.completion and "enabled" or "disabled"))
end, {})

-- Terminal toggle with Alt+; is defined in lua/plugins/ui.lua (snacks.nvim keys spec)

-- Copy file reference to clipboard for Claude Code
local function current_file_ref_path()
  local file = vim.fn.expand("%:.")
  if file ~= "" and vim.bo.buftype ~= "nofile" and not file:match("^codediff://") then
    return file
  end

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return file
  end

  local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
  if not session then
    return file
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local path
  if current_buf == session.original_bufnr then
    path = session.original_path
  elseif current_buf == session.modified_bufnr then
    path = session.modified_path
  elseif session.explorer and current_buf == session.explorer.bufnr then
    path = session.explorer.current_file_path or session.modified_path or session.original_path
  else
    path = session.modified_path or session.original_path
  end

  if not path or path == "" then
    return file
  end

  if session.git_root and path:sub(1, #session.git_root + 1) == session.git_root .. "/" then
    return path:sub(#session.git_root + 2)
  end
  return path
end

vim.keymap.set("n", "<Leader>at", function()
  local file = current_file_ref_path()
  local line = vim.fn.line(".")
  local ref = "@" .. file .. " (line " .. line .. ")"
  vim.fn.setreg("+", ref)
  vim.notify("Copied: " .. ref)
end, { desc = "Copy @file (line) to clipboard" })

vim.keymap.set("v", "<Leader>at", function()
  local file = current_file_ref_path()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local ref
  if start_line == end_line then
    ref = "@" .. file .. " (line " .. start_line .. ")"
  else
    ref = "@" .. file .. " (lines " .. start_line .. "-" .. end_line .. ")"
  end
  vim.fn.setreg("+", ref)
  vim.notify("Copied: " .. ref)
end, { desc = "Copy @file (lines) to clipboard" })
