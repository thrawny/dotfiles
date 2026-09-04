{
  pkgs,
  voxtype,
  ...
}:
{
  imports = [ voxtype.homeManagerModules.default ];

  programs.voxtype = {
    enable = true;
    package = voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    service.enable = true;
    settings = {
      audio.device = "pipewire";
      hotkey.enabled = false;
      osd.frontend = "native";
      output = {
        mode = "paste";
        paste_keys = "ctrl+shift+v";
        restore_clipboard = true;
        restore_clipboard_delay_ms = 300;
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
        "neary" = "Niri";
        "veiland" = "Wayland";
        "neovim" = "Neovim";
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
