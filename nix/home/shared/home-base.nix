{
  config,
  homeSource,
  lib,
  pkgs,
  ...
}@args:
let
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  repoBacked = homeSource == "repo";
  storeBacked = homeSource == "store";
  gitIdentity = {
    name = null;
    email = null;
  }
  // (args.gitIdentity or { });
  configPath =
    rel: if repoBacked then "${dotfiles}/config/${rel}" else containerAssets.config + "/${rel}";
  configSource =
    rel: if repoBacked then config.lib.file.mkOutOfStoreSymlink (configPath rel) else configPath rel;
in
{
  _module.args = {
    inherit
      configPath
      configSource
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
    extraOptions = ''
      !include access-tokens.conf
    '';
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://cache.numtide.com"
        "https://nix-community.cachix.org"
        "https://thrawny.cachix.org"
      ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "thrawny.cachix.org-1:RCPvyTqc1GNCRnAhHAaP2ZOnsWoaZQyhhCqf33lMOcg="
      ];
    };
  };

  home = {
    stateVersion = "24.05";

    activation.createNixAccessTokensFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      tokens_file="${config.xdg.configHome}/nix/access-tokens.conf"
      if [ ! -e "$tokens_file" ]; then
        install -d -m0700 "$(dirname "$tokens_file")"
        : > "$tokens_file"
        chmod 0600 "$tokens_file"
      fi
    '';

    sessionPath = [
      "$HOME/.cargo/bin"
      "$HOME/.bun/bin"
      "$HOME/.local/share/nix-wrappers/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.local/share/pnpm"
      "$HOME/.local/bin"
      "$HOME/go/bin"
    ]
    ++ lib.optionals repoBacked [ "${config.home.homeDirectory}/dotfiles/bin" ]
    ++ lib.optionals storeBacked [ "${containerAssets.bin}" ];

    sessionVariables = {
      FZF_CTRL_R_OPTS = "--bind esc:print-query --bind ctrl-c:print-query";
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONPYCACHEPREFIX = "${config.xdg.cacheHome}/python-pycache";
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
