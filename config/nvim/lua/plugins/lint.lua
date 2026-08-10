local function normalized_path(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function workspace_contains_module(gowork, module_root, dirname)
  local ok, result = pcall(function()
    return vim.system({ "go", "work", "edit", "-json" }, { cwd = dirname, text = true }):wait()
  end)
  if not ok or result.code ~= 0 then
    return true
  end

  local decoded_ok, workspace = pcall(vim.json.decode, result.stdout or "")
  if not decoded_ok or type(workspace) ~= "table" then
    return true
  end

  local workspace_root = vim.fn.fnamemodify(gowork, ":h")
  for _, use in ipairs(workspace.Use or {}) do
    if use.DiskPath then
      local use_path = use.DiskPath
      if vim.fn.isabsolutepath(use_path) == 0 then
        use_path = workspace_root .. "/" .. use_path
      end
      if normalized_path(use_path) == module_root then
        return true
      end
    end
  end
  return false
end

local function golangcilint_context()
  local filename = normalized_path(vim.api.nvim_buf_get_name(0))
  local dirname = vim.fn.fnamemodify(filename, ":h")
  local context = { cwd = dirname, target = filename }

  local ok, result = pcall(function()
    return vim.system({ "go", "env", "GOMOD", "GOWORK" }, { cwd = dirname, text = true }):wait()
  end)
  if not ok or result.code ~= 0 then
    return context
  end

  local lines = vim.split(vim.trim(result.stdout or ""), "\n", { plain = true })
  local gomod = vim.trim(lines[1] or "")
  local gowork = vim.trim(lines[2] or "")
  local has_module = gomod ~= "" and gomod ~= "/dev/null"
  local has_workspace = gowork ~= "" and gowork ~= "off" and gowork ~= "/dev/null"

  if has_module then
    local module_root = normalized_path(vim.fn.fnamemodify(gomod, ":h"))
    local relative_dir = vim.fs.relpath(module_root, dirname)
    context.cwd = module_root
    context.target = relative_dir and (relative_dir == "." and "." or "./" .. relative_dir) or filename

    -- A parent go.work can intentionally omit this module. Go still reports
    -- both GOMOD and GOWORK, but golangci-lint then fails during typechecking.
    if has_workspace and not workspace_contains_module(gowork, module_root, dirname) then
      context.env = vim.fn.environ()
      context.env.GOWORK = "off"
    end
  elseif has_workspace then
    local workspace_root = normalized_path(vim.fn.fnamemodify(gowork, ":h"))
    local relative_dir = vim.fs.relpath(workspace_root, dirname)
    context.cwd = workspace_root
    context.target = relative_dir and (relative_dir == "." and "." or "./" .. relative_dir) or filename
  end

  return context
end

local function golangcilint_linter()
  local linter = vim.deepcopy(require("lint.linters.golangcilint"))
  local context = golangcilint_context()
  linter.cwd = context.cwd
  linter.env = context.env
  if linter.args and #linter.args > 0 then
    linter.args[#linter.args] = context.target
  end
  return linter
end

return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    opts.linters_by_ft = opts.linters_by_ft or {}
    -- Disable markdown linting (markdownlint-cli2 not installed)
    opts.linters_by_ft.markdown = {}
    -- Disable SQL linting
    opts.linters_by_ft.sql = {}
    opts.linters_by_ft.mysql = {}
    opts.linters_by_ft.plsql = {}

    opts.linters = opts.linters or {}
    opts.linters.golangcilint = golangcilint_linter
  end,
}
