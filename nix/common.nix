{ lib, pkgs, ... }:

let
  username = "jonas";
  dotfiles = "/home/${username}/dotfiles";
in
{
  networking.hostName = lib.mkDefault "nixos";
  system.stateVersion = "25.11";

  services.xserver.enable = false;
  programs.hyprland.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "Hyprland";
      user = username;
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "wheel" "video" "audio" "input" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    neovim
    tmux
    ripgrep
    wl-clipboard
    waybar
    foot
    kitty
    fuzzel
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${username} =
    { lib, config, ... }:
    let
      hmLib = lib.hm;
      seedExample = example: destination:
        hmLib.dag.entryBefore [ "linkGeneration" ] ''
          repo=${lib.escapeShellArg dotfiles}
          example_path="$repo/${example}"
          dest_path="$repo/${destination}"
          if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
            install -Dm0644 "$example_path" "$dest_path"
          fi
        '';
    in
    {
      home = {
        username = username;
        homeDirectory = "/home/${username}";
        stateVersion = "24.05";
      };

      home.file.".zshrc".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/zsh/zshrc";
      home.file.".tmux.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/tmux/tmux.conf";
      home.file.".gitconfig".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/git/gitconfig";
      home.file.".gitignoreglobal".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/git/gitignoreglobal";

      xdg.configFile."nvim".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/nvim";
      xdg.configFile."ghostty".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/ghostty";
      xdg.configFile."direnv".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/direnv";
      xdg.configFile."k9s".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/k9s";
      xdg.configFile."starship/starship.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/starship/starship.toml";
      home.file.".default-npm-packages".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/npm/default-packages";

      xdg.configFile."hypr".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr";

      home.activation.seedClaudeSettings =
        seedExample "config/claude/settings.example.json" "config/claude/settings.json";
      home.activation.seedCursorSettings =
        seedExample "config/cursor/settings.example.json" "config/cursor/settings.json";
    };
}
