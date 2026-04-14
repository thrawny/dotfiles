{
  pkgs,
  lib,
  claude-code-nix,
  llm-agents,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv.hostPlatform) system;
  claudePkgs = claude-code-nix.packages.${system};
  llmPkgs = llm-agents.packages.${system};
in
{
  home.packages = [
    claudePkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    pkgs.agent-browser
  ]
  ++ lib.optionals isLinux [
    pkgs.bubblewrap
  ];
}
