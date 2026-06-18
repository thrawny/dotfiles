{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv) isDarwin;
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

      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;

      delta = {
        dark = true;
        paging = "never";
        syntax-theme = "Monokai Extended";
        line-numbers = true;
        plus-style = "syntax \"#004466\"";
        plus-emph-style = "syntax \"#0077b3\"";
        plus-non-emph-style = "syntax \"#003355\"";
        minus-style = "syntax \"#660100\"";
        minus-emph-style = "syntax \"#b30100\"";
        minus-non-emph-style = "syntax \"#440100\"";
        line-numbers-minus-style = "#ff6666";
        line-numbers-plus-style = "#66aaff";
        line-numbers-zero-style = "#888888";
      };

    }
    // lib.optionalAttrs isDarwin {
      # macOS: use gh CLI for GitHub credential management
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
    };

    ignores = gitIgnores;
  };
}
