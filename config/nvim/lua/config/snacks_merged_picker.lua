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

local function files_query_for_path(search)
  local query = vim.trim(search or "")
  if query:find("%s") then
    return query:gsub("%s+", ".*")
  end
  return query
end

local function files_finder(opts, ctx)
  local files = require("snacks.picker.source.files")
  local files_ctx = ctx
  local query = files_query_for_path(ctx.filter.search)
  if query ~= ctx.filter.search then
    files_ctx = ctx:clone(opts)
    files_ctx.filter = ctx.filter:clone()
    files_ctx.filter.search = query
  end
  return files.files(opts, files_ctx)
end

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
      {
        source = "files",
        finder = files_finder,
        args = { "--full-path" },
      },
      { source = "grep" },
    },
    format = "file",
    sort = {
      fields = { "source_id", "score:desc", "#text", "idx" },
    },
    matcher = {
      cwd_bonus = true,
      frecency = true,
      sort_empty = true,
    },
    transform = function(item)
      if item.source_id == 1 then
        item.label = "[F]"
      elseif item.source_id == 2 then
        item.label = "[G]"
      end
      return item
    end,
    layout = {
      preset = "default",
      layout = {
        [2] = { win = "preview", width = 0.6 },
      },
    },
    win = {
      input = {
        keys = {
          ["<a-h>"] = false,
          ["<a-i>"] = false,
          ["<c-y>"] = { "toggle_hidden", mode = { "i", "n" } },
          ["<c-o>"] = { "toggle_ignored", mode = { "i", "n" } },
        },
      },
      list = {
        keys = {
          ["<a-h>"] = false,
          ["<a-i>"] = false,
          ["<c-y>"] = "toggle_hidden",
          ["<c-o>"] = "toggle_ignored",
        },
      },
    },
  }

  if overrides then
    opts = vim.tbl_deep_extend("force", opts, overrides)
  end

  return opts
end

return M
