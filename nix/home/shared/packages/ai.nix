{
  pkgs,
  lib,
  llm-agents,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
in
{
  home.packages = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    pkgs.agent-browser
  ]
  ++ lib.optionals isLinux [
    pkgs.bubblewrap
  ];
}
