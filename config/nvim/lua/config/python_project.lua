-- Resolve the type checker a Python project configures, so the editor reports
-- the same diagnostics the project's own tooling does. Projects that configure
-- no checker get no type diagnostics at all.

local M = {}

local function has_section(file, section)
  local fd = io.open(file, "r")
  if not fd then
    return false
  end
  local content = fd:read("*a")
  fd:close()
  return content:find("%[" .. vim.pesc(section) .. "%]") ~= nil
end

local function always()
  return true
end

-- Config files per checker, mapped to the test that decides whether the file
-- actually configures it (a pyproject.toml exists in nearly every project).
local checkers = {
  {
    name = "mypy",
    files = {
      ["mypy.ini"] = always,
      [".mypy.ini"] = always,
      ["pyproject.toml"] = function(file)
        return has_section(file, "tool.mypy")
      end,
      ["setup.cfg"] = function(file)
        return has_section(file, "mypy")
      end,
    },
  },
  {
    name = "basedpyright",
    files = {
      ["pyrightconfig.json"] = always,
      ["pyproject.toml"] = function(file)
        return has_section(file, "tool.basedpyright") or has_section(file, "tool.pyright")
      end,
    },
  },
}

local function find_root(path, files)
  local hits = vim.fs.find(vim.tbl_keys(files), {
    path = path,
    upward = true,
    type = "file",
    limit = math.huge,
  })
  for _, file in ipairs(hits) do
    if files[vim.fs.basename(file)](file) then
      return vim.fs.dirname(file)
    end
  end
end

-- mypy has to run from the project's own environment: the repos pin a mypy
-- version and load plugins (numpy.typing.mypy_plugin) that only resolve there.
local function mypy_command(root)
  local candidates = { root .. "/.venv/bin/mypy" }
  if vim.env.VIRTUAL_ENV then
    table.insert(candidates, vim.env.VIRTUAL_ENV .. "/bin/mypy")
  end
  for _, candidate in ipairs(candidates) do
    if vim.uv.fs_stat(candidate) then
      return { candidate }
    end
  end
  if vim.uv.fs_stat(root .. "/uv.lock") and vim.fn.executable("uv") == 1 then
    return { "uv", "run", "--frozen", "mypy" }
  end
  if vim.fn.executable("mypy") == 1 then
    return { "mypy" }
  end
end

--- Which type checker, if any, the project owning `path` configures.
---@param path string
---@return { name: string, root: string, cmd: string[]? }|nil
function M.type_checker(path)
  if path == "" then
    return nil
  end
  for _, checker in ipairs(checkers) do
    local root = find_root(path, checker.files)
    if root then
      local resolved = { name = checker.name, root = root }
      if checker.name == "mypy" then
        resolved.cmd = mypy_command(root)
      end
      return resolved
    end
  end
end

--- nvim-lint linter for the mypy of the project owning the current buffer.
---@return table
function M.mypy_linter()
  local linter = vim.deepcopy(require("lint.linters.mypy"))
  local checker = M.type_checker(vim.api.nvim_buf_get_name(0))
  if not checker or not checker.cmd then
    return linter
  end
  linter.cmd = checker.cmd[1]
  linter.args = vim.list_extend(vim.list_slice(checker.cmd, 2), linter.args or {})
  linter.cwd = checker.root
  return linter
end

return M
