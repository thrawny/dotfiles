local M = {}

M.exclude = {
  "**/.git/**",
  "**/node_modules/**",
  "**/.venv/**",
  "**/.ruff_cache/**",
  "**/target/**",
  "**/.direnv/**",
  "**/.DS_Store",
}

---@param overrides? table
---@return table
function M.opts(overrides)
  local opts = {
    title = "Find + Grep (cwd)",
    live = true,
    hidden = true,
    ignored = true,
    exclude = vim.deepcopy(M.exclude),
    multi = {
      { source = "files" },
      { source = "grep" },
    },
    format = "file",
    sort = {
      fields = { "score:desc", "source_id", "#text", "idx" },
    },
    matcher = {
      cwd_bonus = true,
      frecency = true,
      sort_empty = true,
    },
  }

  if overrides then
    opts = vim.tbl_deep_extend("force", opts, overrides)
  end

  return opts
end

return M
