local M = {}

local ignored = {
  { path = ".git", kind = "dir" },
  { path = "node_modules", kind = "dir" },
  { path = ".venv", kind = "dir" },
  { path = ".ruff_cache", kind = "dir" },
  { path = "target", kind = "dir" },
  { path = "dist", kind = "dir" },
  { path = ".direnv", kind = "dir" },
  { path = "dbt/logs", kind = "dir" },
  { path = ".next", kind = "dir" },
  { path = ".open-next", kind = "dir" },
  { path = ".DS_Store", kind = "file" },
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
  return vim.tbl_map(function(item)
    if item.kind == "file" then
      return "**/" .. item.path
    end
    return "**/" .. item.path .. "/**"
  end, ignored)
end

return M
