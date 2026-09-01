local M = {}

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local data = file:read("*a")
  file:close()
  return data
end

function M.find()
  local path = vim.uv.cwd()

  while path and path ~= "" do
    local file = path .. "/.lazy.lua"
    if vim.fn.filereadable(file) == 1 then
      local dir = path
      return {
        name = vim.fn.fnamemodify(file, ":~:."),
        import = function()
          -- Trust the project directory once so edits to .lazy.lua do not
          -- require approval after every change.
          if not vim.secure.read(dir) then
            return {}
          end

          local data = read_file(file)
          if not data then
            return {}
          end

          return assert(loadstring(data, "@" .. file))()
        end,
      }
    end

    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
end

return M
