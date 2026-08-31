# Home Manager config for NixOS desktops
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  pkgs,
  username,
  voxtype,
  xremap-flake,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # xremap home-manager module (from flake)
    xremap-flake.homeManagerModules.default
    ./xremap.nix

    # Niri window manager
    ./niri
    ./niri/switcher.nix

    # Hyprland (Lua config; session selectable at the greeter)
    ./hyprland.nix

    # Desktop modules
    ./hypridle.nix
    ./hyprlock.nix
    ./btop.nix
    ./mako.nix
    ./open-url.nix
    ./telegram.nix
    ./walker.nix
    ./waybar.nix
    ./gtk.nix
    ./viewers.nix

    voxtype.homeManagerModules.default
  ];

  programs.voxtype = {
    enable = true;
    package = voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    service.enable = true;
    settings = {
      audio.device = "pipewire";
      hotkey.enabled = false;
      osd.frontend = "native";
      output = {
        mode = "type";
        fallback_to_clipboard = true;
        paste_keys = "shift+insert";
      };
      whisper = {
        mode = "remote";
        language = "en";
        # Work around voxtype#496, which sends the local model name to remote APIs.
        model = "whisper-large-v3-turbo";
        remote_endpoint = "https://api.groq.com/openai";
        remote_model = "whisper-large-v3-turbo";
        remote_timeout_secs = 30;
      };
      text.replacements = {
        "wavois" = "voxtype";
        "nbin" = "nvim";
        "n-bar" = "env var";
        "n var" = "env var";
        ".files" = "dotfiles";
        "simlink" = "symlink";
        "sim linking" = "symlinking";
        "lasergit" = "lazygit";
        "operational shock" = "operational soc";
        "prequel" = "prequal";
        "czu" = "csv";
        "pubview" = "webview";
        "guitar action" = "github action";
        "throney" = "thrawny";
        "cashics" = "cachix";
        "kasex" = "Cachix";
        "zms" = "zmx";
        "groc" = "groq";
        "deer" = "dir";
        "in cus" = "incus";
        "psuedo" = "sudo";
        "cloudcod" = "claude code";
        "Pyre" = "Pi";
        "Kodis" = "Codex";
        "zulius" = "solis";
        "zulu" = "solis";
        "veko" = "weco";
        "cynic cell" = "sinexcel";
        "cmx" = "zmx";
        "inkis" = "incus";
        "hermi" = "hermes";
        ".file" = "dotfile";
      };
    };
  };

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      vesktop # Discord client with Wayland screen sharing support
      voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-native
    ];
  };
}
