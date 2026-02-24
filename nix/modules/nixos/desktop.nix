{
  config,
  pkgs,
  nurPkgs,
  zen-browser,
  walker,
  xremap-flake,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;

  desktopPackages = with pkgs; [
    brightnessctl
    docker-compose
    fastfetch
    gnome-themes-extra
    keyd
    libnotify
    networkmanagerapplet
    pamixer
    pavucontrol
    playerctl
    powertop
    spotify
    waybar
    wl-clipboard
    wtype
    nurPkgs.repos.Ev357.helium
  ];
in
{
  environment.systemPackages = desktopPackages;

  # Pre-trust niri cache so it works on first build (before niri-flake module applies)
  nix.settings = {
    trusted-substituters = [ "https://niri.cachix.org" ];
    trusted-public-keys = [
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  users.users.${username}.extraGroups = [
    "video"
    "audio"
    "input"
  ];

  programs = {
    niri = {
      enable = true;
      package = pkgs.niri-stable;
    };

    # Enable AppImage support
    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  hardware.bluetooth.enable = true;
  networking.networkmanager.enable = true;

  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
      wireplumber.extraConfig."11-bluetooth-policy" = {
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
    };
    greetd = {
      enable = true;
      settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
    };
    blueman.enable = true;

    # Keyd disabled - using xremap instead to avoid double-grab keyboard conflicts
    keyd.enable = false;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.caskaydia-mono
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit
        zen-browser
        walker
        xremap-flake
        ;
    };
    users.${username} = import ../../home/nixos/default.nix;
  };
}
