{ pkgs }:
pkgs.writeShellApplication {
  name = "t3code-preferences";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  text = builtins.readFile ../../scripts/t3code-preferences;
}
