{ lib, ... }:
{
  # Override ghostty settings for macOS
  programs.ghostty.settings = {
    font-size = lib.mkForce 14;
    font-thicken = true;
    font-thicken-strength = 50;
    window-padding-y = lib.mkForce 2;
    macos-option-as-alt = true;

    # macOS needs different escape sequence for shift+enter
    # Each \\ in Nix becomes \ in output, so \\\\\\ becomes \\\
    keybind = lib.mkForce [
      "shift+enter=text:\\\\\\n\\r"
    ];
  };
}
