-- Classifies generated files so pickers can rank them last.
--
-- Two sources, in order of precedence: the repository's own
-- `linguist-generated` gitattributes, then the built-in glob list below.

local M = {}

-- Git-style globs, matched against repo-relative paths.
local builtin = {
  "**/*.pb.go",
  "**/*.pb.gw.go",
  "**/*_gen.go",
  "**/*.gen.*",
  "**/*.generated.*",
  "**/mock_*.go",
  "**/mocks/**",
  "**/*_pb2.py",
  "**/*_pb2.pyi",
  "**/*.min.js",
  "**/*.min.css",
  "**/*.map",
  "**/__snapshots__/**",
  "**/*.snap",
  "**/package-lock.json",
  "**/pnpm-lock.yaml",
  "**/yarn.lock",
  "**/poetry.lock",
  "**/uv.lock",
  "**/Cargo.lock",
  "**/flake.lock",
  "**/go.sum",
  "**/dbt/target/**",
}

---Translate a gitattributes pattern into an LSP-style glob anchored in `dir`.
---@param dir string directory holding the .gitattributes, repo-relative, "" for root
---@param pattern string
---@return string?
local function to_glob(dir, pattern)
  if pattern == "" then
    return nil
  end

  local anchored = pattern:sub(1, 1) == "/"
  if anchored then
    pattern = pattern:sub(2)
  end

  if pattern:sub(-1) == "/" then
    pattern = pattern .. "**"
  end

  -- A pattern without a slash matches by basename at any depth.
  if not anchored and not pattern:sub(1, -2):find("/") then
    pattern = "**/" .. pattern
  end

  if dir ~= "" then
    pattern = dir .. "/" .. pattern
  end

  return pattern
end

---@param line string
---@return string? pattern, boolean? generated
local function parse_attr_line(line)
  line = vim.trim(line)
  if line == "" or line:sub(1, 1) == "#" then
    return nil
  end

  local pattern, rest = line:match("^(%S+)%s+(.*)$")
  if not pattern then
    return nil
  end

  local generated = nil
  for attr in rest:gmatch("%S+") do
    if attr == "linguist-generated" or attr == "linguist-generated=true" then
      generated = true
    elseif attr == "-linguist-generated" or attr == "linguist-generated=false" then
      generated = false
    end
  end

  if generated == nil then
    return nil
  end
  return pattern, generated
end

---@param cwd string
---@return string[]
local function gitattributes_files(cwd)
  local result = vim
    .system({ "git", "-C", cwd, "ls-files", "--cached", "--", ".gitattributes", "*/.gitattributes" }, { text = true })
    :wait()
  if result.code ~= 0 then
    return {}
  end
  return vim.split(result.stdout or "", "\n", { trimempty = true })
end

---Later rules win, so shallower .gitattributes files are listed first.
---@param cwd string
---@return { glob: string, generated: boolean }[]
local function gitattributes_rules(cwd)
  local files = gitattributes_files(cwd)
  table.sort(files, function(a, b)
    local da, db = select(2, a:gsub("/", "")), select(2, b:gsub("/", ""))
    if da ~= db then
      return da < db
    end
    return a < b
  end)

  local rules = {}
  for _, file in ipairs(files) do
    local dir = vim.fn.fnamemodify(file, ":h")
    if dir == "." then
      dir = ""
    end
    for _, line in ipairs(vim.fn.readfile(cwd .. "/" .. file)) do
      local pattern, generated = parse_attr_line(line)
      if pattern then
        local glob = to_glob(dir, pattern)
        if glob then
          table.insert(rules, { glob = glob, generated = generated })
        end
      end
    end
  end
  return rules
end

---@param rules { glob: string, generated: boolean }[]
---@return { lpeg: vim.lpeg.Pattern, generated: boolean }[]
local function compile(rules)
  local compiled = {}
  for _, rule in ipairs(rules) do
    local ok, lpeg = pcall(vim.glob.to_lpeg, rule.glob)
    if ok then
      table.insert(compiled, { lpeg = lpeg, generated = rule.generated })
    end
  end
  return compiled
end

local cache = {}

---Build a `fun(path: string): boolean` for `cwd`, reading its gitattributes once.
---@param cwd string
---@return fun(path: string): boolean
function M.matcher(cwd)
  cwd = vim.fs.normalize(cwd)
  if cache[cwd] then
    return cache[cwd]
  end

  local rules = {}
  for _, glob in ipairs(builtin) do
    table.insert(rules, { glob = glob, generated = true })
  end
  vim.list_extend(rules, gitattributes_rules(cwd))
  local compiled = compile(rules)

  local prefix = cwd .. "/"
  local memo = {}

  local function matcher(path)
    if not path or path == "" then
      return false
    end
    local cached = memo[path]
    if cached ~= nil then
      return cached
    end

    local relative = vim.fs.normalize(path)
    if relative:sub(1, #prefix) == prefix then
      relative = relative:sub(#prefix + 1)
    end

    -- Last matching rule wins, mirroring gitattributes precedence.
    local generated = false
    for _, rule in ipairs(compiled) do
      if rule.lpeg:match(relative) then
        generated = rule.generated
      end
    end

    memo[path] = generated
    return generated
  end

  cache[cwd] = matcher
  return matcher
end

---Drop cached matchers so the next picker re-reads gitattributes.
function M.reset()
  cache = {}
end

return M
