-- Loader for the central dotfiles theme (nix/themes/monokai.json).
-- Nix injects its generated copy; the portable macOS setup links the runtime
-- fallback at ~/.config/dotfiles/theme.json.
local M = {}

local cached

local function read_json(path)
  if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil
end

function M.load()
  if cached then
    return cached
  end
  -- Built with insert so unset candidates (nil) can't truncate the list.
  local candidates = {}
  local function add(path)
    if path and path ~= "" then
      table.insert(candidates, path)
    end
  end
  add(vim.env.DOTFILES_THEME)
  add(vim.g.dotfiles_theme_path)
  add(vim.fn.expand("~/.config/dotfiles/theme.json"))
  for _, path in ipairs(candidates) do
    cached = read_json(path)
    if cached then
      return cached
    end
  end
  error(
    "dotfiles theme not found (checked $DOTFILES_THEME, vim.g.dotfiles_theme_path, ~/.config/dotfiles/theme.json); run `just switch` or `bin/setup-macos`"
  )
end

return M
