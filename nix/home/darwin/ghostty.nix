{ lib, ... }:
{
  # Override ghostty settings for macOS
  programs.ghostty.settings.font-size = lib.mkForce 14;
  programs.ghostty.settings.font-thicken = true;
  programs.ghostty.settings.font-thicken-strength = 50;
  programs.ghostty.settings.window-padding-y = lib.mkForce 2;
  programs.ghostty.settings.macos-option-as-alt = true;

  # macOS needs different escape sequence for shift+enter
  # Each \\ in Nix becomes \ in output, so \\\\\\ becomes \\\
  programs.ghostty.settings.keybind = lib.mkForce [
    "shift+enter=text:\\\\\\n\\r"
  ];
}
