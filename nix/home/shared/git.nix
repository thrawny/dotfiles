{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv) isDarwin;
in
{
  programs.git = {
    enable = true;
    lfs.enable = true;

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

      core = {
        pager = "less -F -X";
        autocrlf = "input";
        editor = ''nvim -c 'autocmd VimLeave * call system("printf \\033c")' '';
      };

      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;

      # gtr (git-tree-restore) custom tool settings
      "gtr \"copy\"" = {
        include = [
          ".env.local"
          ".envrc"
          ".claude/settings.local.json"
        ];
        includeDirs = [
          ".venv"
          "node_modules"
        ];
      };

      "gtr \"editor\"".default = "nvim";
      "gtr \"ai\"".default = "claude";
    }
    // lib.optionalAttrs isDarwin {
      # macOS: use gh CLI for GitHub credential management
      "credential \"https://github.com\"" = {
        helper = [
          ""
          "!/opt/homebrew/bin/gh auth git-credential"
        ];
      };
      "credential \"https://gist.github.com\"" = {
        helper = [
          ""
          "!/opt/homebrew/bin/gh auth git-credential"
        ];
      };
    };

    ignores = [
      # Editors/IDEs
      ".idea"
      ".vscode"
      "*~"

      # OS
      ".DS_Store"

      # Dependencies
      "node_modules"
      ".venv"
      "venv"

      # Python
      "*.pyc"
      ".pytest_cache"

      # Environment/secrets
      ".envrc"
      ".direnv"
      ".secrets"
      ".secrets*"
      ".scrt"
      ".ssh"
      "*.local.json"
      "*.local.md"

      # Terraform
      ".terraform"
      "*.tfstate*"

      # Lab/scratch files
      ".history"
      ".wercker"
      "lab"
      "lab.*"
      "lab*.json"
      "lab-*"
      "*.lab.*"
      "*_lab.py"
      "lab_test.go"
      "Dockerfile.lab"
      "tilt.profile"

      # Tools
      "telepresence.log"
      ".run"
      "tabort*"
      ".spr.yml"
      "*debug_bin*"
      "*.ipynb"

      # Claude/AI tools
      ".claude/plans"
      ".playwright-mcp"

      # Workflow files
      "/progress.md"
      "/handoff.md"
      ".lazy.lua"
    ];
  };
}
