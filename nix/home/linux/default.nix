# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/switcher.nix)
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  pkgs,
  voxtype,
  ...
}:
{
  imports = [
    ./hyprlock.nix
    ./xremap.nix
    voxtype.homeManagerModules.default
  ];

  programs.voxtype = {
    enable = true;
    package = voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    service.enable = true;
    settings = {
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

  home.packages = [ voxtype.packages.${pkgs.stdenv.hostPlatform.system}.osd-native ];
}
