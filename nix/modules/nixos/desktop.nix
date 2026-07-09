{
  config,
  pkgs,
  helium-browser,
  zen-browser,
  walker,
  xremap-flake,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;
  niriSessionCommand = pkgs.writeShellScript "niri-session-with-secrets" ''
    set -e
    if [ -f "$HOME/.secrets" ]; then
      set -a
      . "$HOME/.secrets"
      set +a
    fi
    exec ${config.programs.niri.package}/bin/niri-session
  '';

  desktopPackages = with pkgs; [
    brightnessctl
    fastfetch
    gnome-themes-extra
    keyd
    networkmanagerapplet
    pamixer
    pavucontrol
    playerctl
    powertop
    spotify
    waybar
    wl-clipboard
    wtype
    (helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      installPhase =
        builtins.replaceStrings
          [ "--enable-features=WaylandWindowDecorations" ]
          [ "--enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer" ]
          old.installPhase;

      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];

      # Chromium keeps its ProcessSingleton socket under $TMPDIR. The sandbox
      # gives /tmp a private tmpfs, so sandboxed `helium --new-window` cannot
      # reach the host Helium socket and falls into the "profile in use" path.
      # ~/.cache is bound wholesale into the sandbox; pinning TMPDIR there makes
      # the socket reachable and keeps working across Helium restarts.
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/helium \
          --run 'export TMPDIR="$HOME/.cache/helium"; mkdir -p "$TMPDIR"'

        substituteInPlace $out/share/applications/helium.desktop \
          --replace-fail 'Exec=helium %U' 'Exec=helium --new-window %U'
      '';
    }))
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
    "uinput"
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

  hardware.uinput.enable = true;
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
      settings = {
        initial_session = {
          command = niriSessionCommand;
          user = username;
        };
        default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd ${niriSessionCommand}";
      };
    };
    blueman.enable = true;

    # Keyd disabled - using xremap instead to avoid double-grab keyboard conflicts
    keyd.enable = false;
  };

  fonts = {
    packages = with pkgs; [
      inter
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      nerd-fonts.caskaydia-mono
    ];
    fontconfig = {
      defaultFonts.sansSerif = [
        "Inter"
        "Noto Sans CJK KR"
      ];
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <match>
            <test name="family"><string>Helvetica</string></test>
            <edit name="family" mode="assign" binding="strong"><string>Inter</string></edit>
          </match>
          <match>
            <test name="family"><string>Helvetica Neue</string></test>
            <edit name="family" mode="assign" binding="strong"><string>Inter</string></edit>
          </match>
          <match>
            <test name="family"><string>Arial</string></test>
            <edit name="family" mode="assign" binding="strong"><string>Inter</string></edit>
          </match>
        </fontconfig>
      '';
    };
  };

  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    # niri-flake sets configPackages = [ niri ] with default=gnome;gtk, but
    # config.niri overrides that entirely, so replicate the defaults here.
    # FileChooser must use gtk because the gnome portal delegates to Nautilus
    # which isn't installed.
    config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Access" = "gtk";
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
      "org.freedesktop.impl.portal.Notification" = "gtk";
      "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
    };
  };

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
