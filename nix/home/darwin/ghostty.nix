{ lib, ... }:
{
  # Override ghostty settings for macOS
  programs.ghostty.settings.font-size = lib.mkForce 13;

  # macOS needs different escape sequence for shift+enter
  # Each \\ in Nix becomes \ in output, so \\\\\\ becomes \\\
  programs.ghostty.settings.keybind = lib.mkForce [
    "shift+enter=text:\\\\\\n\\r"
  ];
}
