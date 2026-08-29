{
  pkgs,
  theme,
  themeLib,
  ...
}:
let
  gitIgnores = import ../../lib/git-ignore.nix;
in
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;

    includes = [
      { path = "~/.gitconfig.local"; }
    ];

    settings = {
      pull.rebase = true;

      rebase = {
        autoSquash = true;
        autoStash = true;
      };

      push = {
        default = "simple";
        useForceIfIncludes = true;
      };

      pager.diff = "hunk pager";

      core = {
        pager = "less -F -X";
        autocrlf = "input";
        editor = ''nvim -c 'autocmd VimLeave * call system("printf \\033c")' '';
      };

      "credential \"https://forgejo.tailf85bba.ts.net\"" = {
        helper = "store";
        username = "thrawny";
      };

      "credential \"https://github.com\"" = {
        helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };
      "credential \"https://gist.github.com\"" = {
        helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };

      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;

      delta = themeLib.deltaOptions theme // {
        paging = "never";
      };

    };

    ignores = gitIgnores;
  };
}
