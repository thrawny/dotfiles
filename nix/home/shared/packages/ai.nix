{
  pkgs,
  lib,
  llm-agents,
  thrawny-pkgs,
  ...
}:
let
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
  thrawnyPkgs = thrawny-pkgs.packages.${system};
  acpx = pkgs.writeShellScriptBin "acpx" ''
    npm_acpx="$HOME/.npm-global/bin/acpx"

    if [ ! -x "$npm_acpx" ]; then
      echo "acpx: expected npm global binary at $npm_acpx" >&2
      echo "Install it with: npm install -g acpx" >&2
      exit 127
    fi

    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [ pkgs.libcap ]
    }:/run/current-system/sw/share/nix-ld/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec "$npm_acpx" "$@"
  '';
in
{
  home.packages = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    pkgs.agent-browser
    thrawnyPkgs.firecrawl-cli
  ]
  ++ lib.optionals isLinux [
    pkgs.bubblewrap
  ];

  home.file.".local/share/nix-wrappers/bin/acpx" = lib.mkIf isLinux {
    source = "${acpx}/bin/acpx";
  };
}
