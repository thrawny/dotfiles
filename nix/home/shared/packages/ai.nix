{
  pkgs,
  llm-agents,
  thrawny-pkgs,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
  thrawnyPkgs = thrawny-pkgs.packages.${system};
in
{
  home.packages = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    pkgs.agent-browser
    thrawnyPkgs.acpx
    thrawnyPkgs.firecrawl-cli
    thrawnyPkgs.posthog-cli
  ]
  ++ pkgs.lib.optionals isLinux [
    pkgs.bubblewrap
  ];
}
