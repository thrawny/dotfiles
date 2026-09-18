# Canonical binary caches for this flake's non-nixpkgs inputs. Two consumers:
#
#   nix/modules/system.nix, for NixOS, through nix.settings
#   bin/install-nix-caches, for macOS, through `nix eval --file`
#
# The script exists because Determinate Nix owns /etc/nix/nix.conf on macOS and
# `nix.enable = false` there, so no Nix module can place these settings. Without
# them every llm-agents.nix package such as codex builds from source.
#
# Desktop-only caches stay in nix/modules/desktop.nix. This list is what every
# host needs.
{
  substituters = [
    # llm-agents.nix: codex, claude-code, and friends.
    "https://cache.numtide.com"
    "https://nix-community.cachix.org"
    # thrawny/nix-pkgs plus this repo's own `just cache` bundle.
    "https://thrawny.cachix.org"
    "https://herdr.cachix.org"
    "https://zmx.cachix.org"
  ];

  trustedPublicKeys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "thrawny.cachix.org-1:RCPvyTqc1GNCRnAhHAaP2ZOnsWoaZQyhhCqf33lMOcg="
    "herdr.cachix.org-1:3nH7IStRsS0ASfdonA0DCRR2ZrSCeWitZ7Kwew0cR4I="
    "zmx.cachix.org-1:9E7zdDiSiG9PnSl8RFHbZ3AW2NmIy/7SPK9rRwed7r4="
  ];
}
