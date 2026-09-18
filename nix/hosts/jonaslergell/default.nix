{
  username = "jonas.lergell";
  homeSource = "repo";
  dotfiles = "/Users/jonas.lergell/dotfiles";
  # ~/code is the ~45 work checkouts on this machine (see gita.nix), so personal
  # plugins and configs are cloned to ~/stuff instead.
  devDir = "$HOME/stuff";
  # No gitIdentity: the work email stays out of this public repo, so
  # ~/.gitconfig.local is written by hand on this machine instead.
}
