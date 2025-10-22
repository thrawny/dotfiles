return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux-aware)" },
    { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Navigate down (tmux-aware)" },
    { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Navigate up (tmux-aware)" },
    { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Navigate right (tmux-aware)" },
    { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Navigate to previous (tmux-aware)" },
  },
}
