local M = {}

local ignored = {
  { path = ".git", kind = "dir" },
  { path = "node_modules", kind = "dir" },
  { path = "__pycache__", kind = "dir" },
  { path = ".venv", kind = "dir" },
  { path = ".ruff_cache", kind = "dir" },
  { path = "target", kind = "dir" },
  { path = "dist", kind = "dir" },
  { path = ".direnv", kind = "dir" },
  { path = "dbt/logs", kind = "dir" },
  { path = ".next", kind = "dir" },
  { path = ".open-next", kind = "dir" },
  { path = ".DS_Store", kind = "file" },
  { path = ".sst", kind = "file" },
}

function M.fzf_lua_file_ignore_patterns()
  return vim.tbl_map(function(item)
    local pattern = vim.pesc(item.path)
    if item.kind == "file" then
      return pattern .. "$"
    end
    return pattern .. "/"
  end, ignored)
end

function M.snacks_exclude_globs()
  local globs = {}
  for _, item in ipairs(ignored) do
    if item.kind == "file" then
      table.insert(globs, "**/" .. item.path)
    else
      table.insert(globs, "**/" .. item.path)
      table.insert(globs, "**/" .. item.path .. "/**")
    end
  end
  return globs
end

return M
