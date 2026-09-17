{ pkgs, ... }:
{
  # gita batch-runs git across many checkouts. Host-local because only this
  # machine has the ~45 work repos under ~/code that make it worth having.
  home.packages = [ pkgs.gita ];

  # gita's repo list lives in ~/.config/gita/repos.csv, which it rewrites on
  # every `gita add`/`gita rm`. That file stays mutable and unmanaged; only the
  # command table below is nix-managed.
  #
  # Custom commands shadow gita's built-ins, so redefining `pull` replaces it
  # everywhere. gita's default is a bare `git pull`, which will happily create a
  # merge commit in a repo you had forgotten you were mid-work in. Across ~45
  # checkouts that is how you end up with surprise merges in four of them.
  xdg.configFile."gita/cmds.json".text = builtins.toJSON {
    # Fast-forward only: a repo that cannot fast-forward is reported as failed
    # and left exactly as it was.
    pull = {
      cmd = "git pull --ff-only";
      allow_all = true;
      help = "fast-forward to remote, never merge";
    };

    # Prune deleted remote branches while fetching. Without --prune, stale
    # origin/* refs for merged PR branches accumulate for months.
    fetch = {
      cmd = "git fetch --all --prune";
      allow_all = true;
      help = "fetch all remotes and prune deleted branches";
    };
  };
}
