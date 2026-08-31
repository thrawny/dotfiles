{
  config,
  pkgs,
  helium-browser,
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
    if [ -z "''${VOXTYPE_WHISPER_API_KEY:-}" ] && [ -n "''${GROQ_API_KEY:-}" ]; then
      export VOXTYPE_WHISPER_API_KEY="$GROQ_API_KEY"
    fi
    if [ -n "''${VOXTYPE_WHISPER_API_KEY:-}" ]; then
      systemctl --user import-environment VOXTYPE_WHISPER_API_KEY
    fi
    exec ${config.programs.niri.package}/bin/niri-session
  '';

  hyprlandSessionCommand = pkgs.writeShellScript "hyprland-session-with-secrets" ''
    set -e
    if [ -f "$HOME/.secrets" ]; then
      set -a
      . "$HOME/.secrets"
      set +a
    fi
    exec ${config.programs.hyprland.package}/bin/Hyprland
  '';

  # Session picker entries for tuigreet (F3 menu). Both wrap ~/.secrets.
  mkGreeterSession =
    name: command:
    pkgs.writeTextDir "${name}.desktop" ''
      [Desktop Entry]
      Name=${name}
      Exec=${command}
      Type=Application
    '';
  greeterSessions = pkgs.symlinkJoin {
    name = "greeter-sessions";
    paths = [
      (mkGreeterSession "niri" niriSessionCommand)
      (mkGreeterSession "hyprland" hyprlandSessionCommand)
    ];
  };

  desktopPackages = with pkgs; [
    brightnessctl
    fastfetch
    gnome-themes-extra
    keyd
    nautilus
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

        # Chromium ignores a remote --new-window request without a URL and only
        # focuses an existing window. Supply about:blank only when the desktop
        # entry was launched without a URL.
        cat > $out/bin/helium-new-window <<EOF
        #!${pkgs.runtimeShell}
        if [ "\$#" -eq 0 ]; then
          set -- about:blank
        fi
        exec "$out/bin/helium" --new-window "\$@"
        EOF
        chmod +x $out/bin/helium-new-window

        substituteInPlace $out/share/applications/helium.desktop \
          --replace-fail 'Exec=helium %U' 'Exec=helium-new-window %U'
      '';
    }))
  ];
in
{
  environment.systemPackages = desktopPackages;

  # Pre-trust niri cache so it works on first build (before niri-flake module applies)
  nix.settings = {
    trusted-substituters = [ "https://niri-epireyn.cachix.org" ];
    trusted-public-keys = [
      "niri-epireyn.cachix.org-1:tlVyFN7CtsDT+ZcLPS+ekFWeT1X6X4OqvWqbBMyIzFA="
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
      package = pkgs.niri;
    };

    # Hyprland 0.56+ (core scrolling layout, Lua config). Config lives in
    # config/hypr/ as Lua, symlinked by home/nixos/hyprland.nix.
    hyprland.enable = true;

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
        default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${greeterSessions} --cmd ${niriSessionCommand}";
      };
    };
    blueman.enable = true;
    # Nautilus uses GVfs for trash, removable media, and network locations.
    gvfs.enable = true;

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
    # Keep the lightweight GTK portal for file chooser dialogs; Nautilus is
    # configured separately as the default directory browser.
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
        walker
        xremap-flake
        ;
    };
    users.${username} = import ../home/nixos/default.nix;
  };
}
