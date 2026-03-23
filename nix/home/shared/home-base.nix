{
  config,
  homeSource,
  lib,
  pkgs,
  ...
}@args:
let
  hmLib = lib.hm;
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  excludedSharedSkills = args.excludedSharedSkills or [ ];
  repoBacked = homeSource == "repo";
  storeBacked = homeSource == "store";
  gitIdentity = {
    name = null;
    email = null;
  }
  // (args.gitIdentity or { });
  configPath =
    rel: if repoBacked then "${dotfiles}/config/${rel}" else containerAssets.config + "/${rel}";
  skillPath =
    name: if repoBacked then "${dotfiles}/skills/${name}" else containerAssets.skills + "/${name}";
  skillsRoot = if repoBacked then ../../../skills else containerAssets.skills;
  sharedSkillNames = lib.filter (name: !builtins.elem name excludedSharedSkills) (
    builtins.attrNames (
      lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "." name)) (
        builtins.readDir skillsRoot
      )
    )
  );
  linuxOnlySkills = [
    "wayvoice"
    "skill-eval"
  ];
  noLinuxOnly = lib.filter (name: !builtins.elem name linuxOnlySkills) sharedSkillNames;
  codexSharedSkillNames = lib.filter (
    name: !builtins.elem name (linuxOnlySkills ++ [ "skill-creator" ])
  ) sharedSkillNames;
  claudeSharedSkillNames = lib.filter (
    name: !builtins.elem name (linuxOnlySkills ++ [ "skill-creator" ])
  ) sharedSkillNames;
  configSource =
    rel: if repoBacked then config.lib.file.mkOutOfStoreSymlink (configPath rel) else configPath rel;
  skillFiles =
    base: names:
    lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "${base}/${name}" {
          source =
            if repoBacked then config.lib.file.mkOutOfStoreSymlink (skillPath name) else skillPath name;
        }
      ) names
    );
in
{
  imports = [
    ./home-source-common.nix
    (if repoBacked then ./home-source-repo.nix else ./home-source-store.nix)
  ];

  _module.args = {
    inherit
      claudeSharedSkillNames
      codexSharedSkillNames
      configPath
      configSource
      noLinuxOnly
      skillFiles
      ;
  };

  assertions = [
    {
      assertion = repoBacked || storeBacked;
      message = "dotfiles homeSource must be either repo or store.";
    }
    {
      assertion = repoBacked || containerAssets != null;
      message = "Store-backed home config requires containerAssets to be provided.";
    }
    {
      assertion = (!repoBacked) || dotfiles != null;
      message = "Repo-backed home config requires dotfiles to be provided.";
    }
  ];

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://cache.numtide.com"
        "https://claude-code.cachix.org"
        "https://thrawny.cachix.org"
      ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "thrawny.cachix.org-1:RCPvyTqc1GNCRnAhHAaP2ZOnsWoaZQyhhCqf33lMOcg="
      ];
    };
  };

  home = {
    stateVersion = "24.05";

    sessionVariables = {
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      GOPATH = "$HOME/go";
      PNPM_HOME = "$HOME/.local/share/pnpm";
      EDITOR = "nvim";
      VISUAL = "nvim";
      MANPAGER = "nvim +Man!";
      AWS_PAGER = "";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      LC_CTYPE = "en_US.UTF-8";
      KUBECTL_EXTERNAL_DIFF = "kubectl-dyff";
    };

    activation = {
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude.json"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","editorMode":"vim","hasCompletedOnboarding":true}' > "$claude_json"
        fi
      '';
    };

    file = {
      ".gitconfig.local" = lib.mkIf (gitIdentity.name != null || gitIdentity.email != null) {
        text =
          lib.concatStringsSep "\n" (
            [ "[user]" ]
            ++ lib.optionals (gitIdentity.name != null) [ "\tname = ${gitIdentity.name}" ]
            ++ lib.optionals (gitIdentity.email != null) [ "\temail = ${gitIdentity.email}" ]
          )
          + "\n";
      };
    };
  };
}
