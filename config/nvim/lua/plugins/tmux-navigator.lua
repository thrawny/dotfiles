-- Inside Herdr, bin/herdr-nav forwards ctrl+hjkl to Neovim instead of moving
-- pane focus, so the window moves happen here. Neovim then has to hand focus
-- back to Herdr at the edge, which is what vim-tmux-navigator does for tmux.
local in_herdr = (vim.env.HERDR_PANE_ID or "") ~= "" and (vim.env.TMUX or "") == ""

local function herdr_navigate(direction, wincmd)
  return function()
    local before = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(wincmd)
    if vim.api.nvim_get_current_win() ~= before then
      return
    end
    vim.system({
      vim.env.HERDR_BIN_PATH or "herdr",
      "pane",
      "focus",
      "--direction",
      direction,
      "--pane",
      vim.env.HERDR_PANE_ID,
    })
  end
end

local directions = {
  { key = "<C-h>", wincmd = "h", direction = "left", cmd = "TmuxNavigateLeft", desc = "Navigate Left" },
  { key = "<C-j>", wincmd = "j", direction = "down", cmd = "TmuxNavigateDown", desc = "Navigate Down" },
  { key = "<C-k>", wincmd = "k", direction = "up", cmd = "TmuxNavigateUp", desc = "Navigate Up" },
  { key = "<C-l>", wincmd = "l", direction = "right", cmd = "TmuxNavigateRight", desc = "Navigate Right" },
}

local keys = {}
for _, entry in ipairs(directions) do
  keys[#keys + 1] = {
    entry.key,
    in_herdr and herdr_navigate(entry.direction, entry.wincmd) or ("<cmd>" .. entry.cmd .. "<cr>"),
    desc = entry.desc,
  }
end

return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  -- plugin/tmux_navigator.vim maps ctrl+hjkl itself when it loads, which would
  -- replace the keys above and lose the Herdr handoff. Its own mappings only
  -- know how to reach tmux, so drop them under Herdr.
  init = in_herdr and function()
    vim.g.tmux_navigator_no_mappings = 1
  end or nil,
  keys = keys,
}
