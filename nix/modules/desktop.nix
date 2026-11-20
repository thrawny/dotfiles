{
  config,
  pkgs,
  helium-browser,
  xremap-flake,
  ...
}:
let
  cfg = config.dotfiles;
  inherit (cfg) username;
  # uwsm gives Hyprland a systemd session with the graphical-session.target
  # lifecycle, so user services (xremap, hypridle, wpaperd) run in it.
  hyprlandSessionCommand = pkgs.writeShellScript "hyprland-session-with-secrets" ''
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
    exec ${config.programs.uwsm.package}/bin/uwsm start -- hyprland-uwsm.desktop
  '';

  # Session picker entries for tuigreet (F3 menu).
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

  users.users.${username}.extraGroups = [
    "video"
    "audio"
    "input"
    "uinput"
  ];

  programs = {
    # Hyprland 0.56+ (core scrolling layout, Lua config). Config lives in
    # config/hypr/ as Lua, symlinked by home/nixos/hyprland.nix.
    hyprland = {
      enable = true;
      withUWSM = true;
    };

    # Enable AppImage support
    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  # Hyprlock handles fingerprints natively; PAM supplies password authentication.
  security.pam.services.hyprlock.fprintAuth = false;

  hardware.uinput.enable = true;
  hardware.bluetooth.enable = true;
  networking.networkmanager.enable = true;

  services = {
    gnome.gnome-keyring.enable = true;
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
          command = hyprlandSessionCommand;
          user = username;
        };
        default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${greeterSessions} --cmd ${hyprlandSessionCommand}";
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
  };

  home-manager = {
    extraSpecialArgs = {
      inherit xremap-flake;
    };
    users.${username} = import ../home/nixos/default.nix;
  };
}
