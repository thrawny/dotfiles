{ lib, ... }:
{
  # Override ghostty settings for macOS
  programs.ghostty.settings = {
    font-size = lib.mkForce 14;
    font-thicken = true;
    font-thicken-strength = 50;
    window-padding-y = lib.mkForce 2;
    macos-option-as-alt = true;
  };
}
